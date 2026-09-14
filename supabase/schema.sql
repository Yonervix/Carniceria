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

-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 3
--  Caja diaria, ventas, mermas y desposte.
--  Todas las mutaciones de stock/caja pasan por RPC
--  (nunca insert directo desde el cliente).
--  Concatenado al final: no modificar lo anterior.
-- ============================================================

create table public.caja (
  id uuid default gen_random_uuid() primary key,
  fecha date not null default current_date,
  abierta boolean not null default true,
  efectivo_inicial numeric(12, 2) not null default 0 check (efectivo_inicial >= 0),
  ventas_total numeric(12, 2) not null default 0,
  creada_por uuid references auth.users on delete set null,
  abierta_at timestamptz not null default now(),
  cerrada_at timestamptz,
  cerrada_por uuid references auth.users on delete set null,
  efectivo_final numeric(12, 2),
  constraint caja_unica_dia unique (fecha)
);

create index idx_caja_fecha on public.caja (fecha desc);

create table public.ventas (
  id uuid default gen_random_uuid() primary key,
  caja_id uuid not null references public.caja on delete restrict,
  subtotal numeric(12, 2) not null check (subtotal >= 0),
  creada_por uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

create index idx_ventas_caja on public.ventas (caja_id, created_at desc);

create table public.venta_items (
  id uuid default gen_random_uuid() primary key,
  venta_id uuid not null references public.ventas on delete cascade,
  producto_id uuid not null references public.products on delete restrict,
  nombre text not null,
  modo_venta public.modo_venta not null,
  medida text,
  cantidad numeric(10, 3) not null check (cantidad > 0),
  precio numeric(12, 2) not null,
  subtotal numeric(12, 2) not null
);

create index idx_venta_items_venta on public.venta_items (venta_id);

create table public.desposte (
  id uuid default gen_random_uuid() primary key,
  origen_id uuid references public.products on delete restrict,
  origen_nombre text not null,
  peso_origen numeric(10, 3) not null check (peso_origen > 0),
  nota text,
  creado_por uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

create table public.desposte_items (
  id uuid default gen_random_uuid() primary key,
  desposte_id uuid not null references public.desposte on delete cascade,
  destino_id uuid references public.products on delete restrict,
  destino_nombre text not null,
  peso numeric(10, 3) not null check (peso > 0)
);

-- -------------------- RLS BLOQUE 3 --------------------

alter table public.caja enable row level security;
alter table public.ventas enable row level security;
alter table public.venta_items enable row level security;
alter table public.desposte enable row level security;
alter table public.desposte_items enable row level security;

create policy "Lectura de caja"
  on public.caja for select to authenticated using (true);
create policy "Jefe gestiona caja"
  on public.caja for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura de ventas"
  on public.ventas for select to authenticated using (true);
create policy "Jefe gestiona ventas"
  on public.ventas for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura de items de venta"
  on public.venta_items for select to authenticated using (true);
create policy "Jefe gestiona items de venta"
  on public.venta_items for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura de despostes"
  on public.desposte for select to authenticated using (true);
create policy "Jefe gestiona despostes"
  on public.desposte for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

create policy "Lectura de items de desposte"
  on public.desposte_items for select to authenticated using (true);
create policy "Jefe gestiona items de desposte"
  on public.desposte_items for all to authenticated using (public.es_jefe()) with check (public.es_jefe());

-- -------------------- MOTOR DE MOVIMIENTOS --------------------

create or replace function public.aplicar_movimiento(
  p_producto_id uuid,
  p_cambio numeric(10, 3),
  p_concepto public.concepto_movimiento,
  p_nota text default null
) returns numeric(10, 3)
language plpgsql security definer set search_path = public as $$
declare
  v_saldo numeric(10, 3);
begin
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

  return v_saldo;
end;
$$;

create or replace function public.ajustar_existencia(
  p_producto_id uuid,
  p_cambio numeric(10, 3),
  p_concepto public.concepto_movimiento default 'ajuste',
  p_nota text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ajustar existencias';
  end if;
  perform public.aplicar_movimiento(p_producto_id, p_cambio, p_concepto, p_nota);
end;
$$;

-- -------------------- CAJA DIARIA --------------------

create or replace function public.abrir_caja(
  p_efectivo_inicial numeric(12, 2) default 0
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe abre la caja';
  end if;
  if exists (select 1 from public.caja where fecha = current_date) then
    raise exception 'La caja de hoy ya fue abierta';
  end if;

  insert into public.caja (fecha, efectivo_inicial, creada_por)
  values (current_date, coalesce(p_efectivo_inicial, 0), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.cerrar_caja(p_efectivo_final numeric(12, 2)) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe cierra la caja';
  end if;

  update public.caja
  set abierta = false,
      cerrada_at = now(),
      cerrada_por = auth.uid(),
      efectivo_final = p_efectivo_final
  where fecha = current_date and abierta;

  if not found then
    raise exception 'No hay caja abierta para cerrar';
  end if;
end;
$$;

-- -------------------- VENTA --------------------

create or replace function public.registrar_venta(p_items jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_caja public.caja%rowtype;
  v_item jsonb;
  v_producto record;
  v_cantidad numeric(10, 3);
  v_subtotal numeric(12, 2);
  v_total numeric(12, 2) := 0;
  v_venta_id uuid;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene articulos';
  end if;

  select * into v_caja
  from public.caja
  where fecha = current_date
  order by abierta_at desc
  limit 1;

  if not found or not v_caja.abierta then
    raise exception 'No hay caja abierta para el dia de hoy';
  end if;

  insert into public.ventas (caja_id, subtotal, creada_por)
  values (v_caja.id, 0, auth.uid())
  returning id into v_venta_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select p.id, p.nombre, p.precio, p.modo_venta, p.medida
    into v_producto
    from public.products p
    where p.id = (v_item->>'producto_id')::uuid and p.activo;

    if not found then
      raise exception 'Producto invalido o inactivo';
    end if;

    v_cantidad := (v_item->>'cantidad')::numeric(10, 3);
    v_subtotal := round(v_producto.precio * v_cantidad, 2);

    insert into public.venta_items (venta_id, producto_id, nombre, modo_venta, medida, cantidad, precio, subtotal)
    values (v_venta_id, v_producto.id, v_producto.nombre, v_producto.modo_venta, v_producto.medida,
            v_cantidad, v_producto.precio, v_subtotal);

    perform public.aplicar_movimiento(v_producto.id, -v_cantidad, 'venta', 'Venta');
    v_total := v_total + v_subtotal;
  end loop;

  update public.ventas set subtotal = v_total where id = v_venta_id;
  update public.caja set ventas_total = ventas_total + v_total where id = v_caja.id;

  return v_venta_id;
end;
$$;

-- -------------------- MERMA --------------------

create or replace function public.registrar_merma(
  p_producto_id uuid,
  p_cantidad numeric(10, 3),
  p_nota text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_cantidad <= 0 then
    raise exception 'Cantidad invalida';
  end if;
  perform public.aplicar_movimiento(p_producto_id, -p_cantidad, 'merma', p_nota);
end;
$$;

-- -------------------- DESPOSTE --------------------

create or replace function public.registrar_desposte(
  p_origen_id uuid,
  p_peso_origen numeric(10, 3),
  p_destinos jsonb,
  p_nota text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_item jsonb;
  v_nombre text;
  v_total numeric(10, 3) := 0;
  v_peso numeric(10, 3);
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe realiza despostes';
  end if;
  if p_origen_id is null or p_peso_origen <= 0 or p_destinos is null
     or jsonb_array_length(p_destinos) = 0 then
    raise exception 'Parametros invalidos';
  end if;

  for v_item in select * from jsonb_array_elements(p_destinos) loop
    v_total := v_total + (v_item->>'peso')::numeric(10, 3);
  end loop;
  if v_total <= 0 or v_total > p_peso_origen then
    raise exception 'La suma de destinos debe ser positiva y no superar el peso de origen';
  end if;

  select p.nombre into v_nombre from public.products p where p.id = p_origen_id;
  if v_nombre is null then
    raise exception 'Origen no encontrado';
  end if;

  insert into public.desposte (origen_id, origen_nombre, peso_origen, nota, creado_por)
  values (p_origen_id, v_nombre, p_peso_origen, p_nota, auth.uid())
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_destinos) loop
    select p.nombre into v_nombre
    from public.products p
    where p.id = (v_item->>'producto_id')::uuid;

    if v_nombre is null then
      raise exception 'Destino no encontrado';
    end if;

    v_peso := (v_item->>'peso')::numeric(10, 3);
    insert into public.desposte_items (desposte_id, destino_id, destino_nombre, peso)
    values (v_id, (v_item->>'producto_id')::uuid, v_nombre, v_peso);

    perform public.aplicar_movimiento((v_item->>'producto_id')::uuid, v_peso, 'desposte', 'Desposte');
  end loop;

  perform public.aplicar_movimiento(p_origen_id, -p_peso_origen, 'desposte', p_nota);
  return v_id;
end;
$$;

-- -------------------- REALTIME BLOQUE 3 --------------------

do $$
begin
  begin
    alter publication supabase_realtime add table public.caja;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.ventas;
  exception when duplicate_object then null;
  end;
end $$;

alter table public.caja replica identity full;

-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 4
--  Acceso y sesión: el trigger de perfil NO confía en el rol
--  enviado desde el cliente (siempre 'carnicero'); el puesto de
--  jefe se reclama una sola vez o lo asigna otro jefe.
-- ============================================================

create or replace function public.asignar_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nombre, rol)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', 'Carnicero'),
    'carnicero'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.existe_jefe() returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles where rol = 'jefe');
$$;

create or replace function public.reclamar_jefe() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.profiles where rol = 'jefe') then
    raise exception 'Ya existe un jefe en la carniceria';
  end if;
  update public.profiles set rol = 'jefe' where id = auth.uid();
  if not found then
    raise exception 'Perfil no encontrado';
  end if;
end;
$$;

create or replace function public.registrar_alta_producto(
  p_nombre text,
  p_descripcion text default null,
  p_categoria_slug text default 'res',
  p_modo_venta public.modo_venta default 'unit',
  p_medida text default null,
  p_precio numeric(12, 2) default 0,
  p_precio_compra numeric(12, 2) default null,
  p_cantidad_inicial numeric(10, 3) default 0
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_categoria_id uuid;
  v_producto_id uuid;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe da de alta productos';
  end if;
  if p_nombre is null or trim(p_nombre) = '' then
    raise exception 'El nombre es obligatorio';
  end if;
  if exists (
    select 1 from public.products
    where lower(nombre) = lower(trim(p_nombre)) and activo
  ) then
    raise exception 'Ya existe un producto con ese nombre';
  end if;
  if p_precio < 0 or p_precio_compra < 0 then
    raise exception 'Los precios no pueden ser negativos';
  end if;
  if p_modo_venta = 'weight' and p_medida not in ('kg', 'lb') then
    raise exception 'Un producto por peso necesita su medida (kg o lb)';
  end if;
  if p_modo_venta = 'unit' then
    p_medida := null;
  end if;
  if p_cantidad_inicial < 0 then
    raise exception 'La cantidad inicial no puede ser negativa';
  end if;

  select id into v_categoria_id
  from public.categories
  where slug = p_categoria_slug;
  if not found then
    raise exception 'Categoria invalida';
  end if;

  insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra, activo)
  values (trim(p_nombre), nullif(trim(coalesce(p_descripcion, '')), ''), v_categoria_id,
          p_modo_venta, p_medida, p_precio, p_precio_compra, true)
  returning id into v_producto_id;

  if p_cantidad_inicial > 0 then
    perform public.ajustar_existencia(v_producto_id, p_cantidad_inicial, 'inicial', 'Alta de producto');
  end if;

  return v_producto_id;
end;
$$;