-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 1
--  Estructura base: profiles, categories, products,
--  inventory (numeric(10,3)) + ledger, RLS y Realtime.
--  Ejecutar completo en Supabase SQL Editor.
-- ============================================================

create extension if not exists pgcrypto;

create type public.rol_usuario as enum ('jefe', 'carnicero');
create type public.modo_venta as enum ('weight', 'unit');
create type public.concepto_movimiento as enum ('inicial', 'compra', 'venta', 'merma', 'desposte', 'ajuste');

-- -------------------- PERFILES / AUTH --------------------

create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  nombre text not null default '',
  rol public.rol_usuario not null default 'carnicero',
  created_at timestamptz not null default now()
);

create or replace function public.asignar_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nombre, rol)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', 'Carnicero'),
    coalesce((new.raw_user_meta_data->>'rol')::public.rol_usuario, 'carnicero')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.asignar_perfil();

create or replace function public.es_jefe() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and rol = 'jefe'
  );
$$;

-- -------------------- CATÁLOGO --------------------

create table public.categories (
  id uuid default gen_random_uuid() primary key,
  slug text not null unique,
  nombre text not null unique,
  descripcion text,
  orden integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid default gen_random_uuid() primary key,
  nombre text not null,
  descripcion text,
  categoria_id uuid references public.categories on delete set null,
  modo_venta public.modo_venta not null default 'unit',
  medida text,
  precio numeric(12, 2) not null default 0,
  precio_compra numeric(12, 2),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_products_medida check (
    (modo_venta = 'unit' and medida is null) or
    (modo_venta = 'weight' and medida in ('kg', 'lb'))
  )
);

create index idx_products_categoria on public.products (categoria_id);
create index idx_products_activo on public.products (activo) where activo;

insert into public.categories (slug, nombre, descripcion, orden) values
  ('res',        'Res',        'Cortes de vacuno',  1),
  ('cerdo',      'Cerdo',      'Cortes de porcino', 2),
  ('pollo',      'Pollo',      'Aves frescas',      3),
  ('elaborados', 'Elaborados', 'Productos de la casa', 4)
on conflict (slug) do nothing;

-- -------------------- INVENTARIO --------------------

create table public.inventory (
  producto_id uuid primary key references public.products on delete cascade,
  cantidad numeric(10, 3) not null default 0 check (cantidad >= 0),
  stock_minimo numeric(10, 3) not null default 0 check (stock_minimo >= 0),
  ubicacion text,
  updated_at timestamptz not null default now()
);

create table public.inventory_movements (
  id bigint generated always as identity primary key,
  producto_id uuid not null references public.products on delete cascade,
  concepto public.concepto_movimiento not null,
  cambio numeric(10, 3) not null,
  saldo numeric(10, 3) not null,
  nota text,
  creado_por uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

create index idx_movimientos_producto
  on public.inventory_movements (producto_id, created_at desc);

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_products_updated_at
  before update on public.products
  for each row execute procedure public.set_updated_at();

create trigger trg_inventory_updated_at
  before update on public.inventory
  for each row execute procedure public.set_updated_at();

create or replace function public.crear_inventario_inicial() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.inventory (producto_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger trg_products_inventario
  after insert on public.products
  for each row execute procedure public.crear_inventario_inicial();

-- -------------------- VISTA VIVA --------------------

create or replace view public.inventario_vivo
with (security_invoker = true)
as
select
  p.id,
  p.nombre,
  p.descripcion,
  p.modo_venta,
  p.medida,
  p.precio,
  c.slug as categoria,
  c.nombre as categoria_nombre,
  i.cantidad,
  i.stock_minimo as minimo,
  i.ubicacion,
  (i.cantidad <= i.stock_minimo) as en_minimo
from public.products p
left join public.categories c on c.id = p.categoria_id
left join public.inventory i on i.producto_id = p.id
where p.activo = true;

-- -------------------- RLS --------------------

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;

create policy "Perfil propio" on public.profiles
  for select to authenticated using (auth.uid() = id);
create policy "Jefe edita perfiles" on public.profiles
  for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura del catalogo" on public.categories
  for select to authenticated using (true);
create policy "Jefe gestiona categorias" on public.categories
  for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura del catalogo" on public.products
  for select to authenticated using (true);
create policy "Jefe gestiona productos" on public.products
  for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura del inventario" on public.inventory
  for select to authenticated using (true);
create policy "Jefe gestiona inventario" on public.inventory
  for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura de movimientos" on public.inventory_movements
  for select to authenticated using (true);
create policy "Jefe gestiona movimientos" on public.inventory_movements
  for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

-- -------------------- RPC SEGURO --------------------

create or replace function public.ajustar_existencia(
  p_producto_id uuid,
  p_cambio numeric(10, 3),
  p_concepto public.concepto_movimiento default 'ajuste',
  p_nota text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_saldo numeric(10, 3);
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ajustar existencias';
  end if;
  if p_producto_id is null or p_cambio = 0 then
    raise exception 'Parametros invalidos';
  end if;

  update public.inventory
  set cantidad = cantidad + p_cambio,
      updated_at = now()
  where producto_id = p_producto_id
  returning cantidad into v_saldo;

  if v_saldo is null then
    raise exception 'Producto no encontrado';
  end if;
  if v_saldo < 0 then
    raise exception 'La existencia no puede quedar negativa';
  end if;

  insert into public.inventory_movements (producto_id, concepto, cambio, saldo, nota, creado_por)
  values (p_producto_id, p_concepto, p_cambio, v_saldo, p_nota, auth.uid());
end;
$$;

-- -------------------- REALTIME --------------------

do $$
begin
  begin
    alter publication supabase_realtime add table public.inventory;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.products;
  exception when duplicate_object then null;
  end;
end $$;

alter table public.inventory replica identity full;