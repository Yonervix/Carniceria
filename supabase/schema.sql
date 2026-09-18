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

-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 5
--  Imagen en productos, categorías dinámicas, historial de
--  caja y anulación de ventas (solo jefe).
--  Idempotente: se puede re-ejecutar completo en SQL Editor.
-- ============================================================
--  Imagen en productos, categorías dinámicas, historial de
--  caja y anulación de ventas (solo jefe).
--  Idempotente: se puede re-ejecutar completo en SQL Editor.
-- ============================================================

do $$
begin
  alter type public.concepto_movimiento add value if not exists 'anulacion';
exception when duplicate_object then null;
end $$;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'products' and column_name = 'imagen_url'
  ) then
    alter table public.products add column imagen_url text;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'ventas' and column_name = 'anulada'
  ) then
    alter table public.ventas
      add column anulada boolean not null default false,
      add column anulada_por uuid,
      add column anulada_at timestamptz,
      add column motivo_anulacion text;
  end if;
end $$;

drop view if exists public.inventario_vivo;

create or replace view public.inventario_vivo
with (security_invoker = true)
as
select
  p.id,
  p.nombre,
  p.descripcion,
  p.imagen_url,
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

create or replace function public.registrar_alta_producto(
  p_nombre text,
  p_descripcion text default null,
  p_categoria_slug text default 'res',
  p_modo_venta public.modo_venta default 'unit',
  p_medida text default null,
  p_precio numeric(12, 2) default 0,
  p_precio_compra numeric(12, 2) default null,
  p_cantidad_inicial numeric(10, 3) default 0,
  p_imagen_url text default null
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

  insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra, activo, imagen_url)
  values (trim(p_nombre), nullif(trim(coalesce(p_descripcion, '')), ''), v_categoria_id,
          p_modo_venta, p_medida, p_precio, p_precio_compra, true,
          nullif(trim(coalesce(p_imagen_url, '')), ''))
  returning id into v_producto_id;

  if p_cantidad_inicial > 0 then
    perform public.ajustar_existencia(v_producto_id, p_cantidad_inicial, 'inicial', 'Alta de producto');
  end if;

  return v_producto_id;
end;
$$;

create or replace function public.registrar_categoria(p_nombre text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_slug text;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe crea categorias';
  end if;
  if p_nombre is null or trim(p_nombre) = '' then
    raise exception 'El nombre de la categoria es obligatorio';
  end if;
  v_slug := lower(regexp_replace(trim(p_nombre), '[^a-z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  if v_slug = '' then
    v_slug := 'generica';
  end if;
  insert into public.categories (slug, nombre, orden)
  values (v_slug, trim(p_nombre), coalesce((select max(orden) from public.categories), 0) + 1)
  on conflict (slug) do update set nombre = excluded.nombre;
  return v_slug;
end;
$$;

create or replace function public.ventas_del_dia(p_caja_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      v.id,
      v.subtotal,
      v.anulada,
      v.created_at,
      coalesce(p.nombre, 'Desconocido') as carnicero,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('nombre', i.nombre, 'cantidad', i.cantidad, 'subtotal', i.subtotal)
        )
        from public.venta_items i
        where i.venta_id = v.id
      ), '[]'::jsonb) as articulos
    from public.ventas v
    left join public.profiles p on p.id = v.creada_por
    where v.caja_id = p_caja_id
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.anular_venta(p_venta_id uuid, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_venta record;
  v_item record;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede anular ventas';
  end if;
  if p_venta_id is null then
    raise exception 'Venta invalida';
  end if;

  select * into v_venta
  from public.ventas
  where id = p_venta_id
  for update;

  if not found then
    raise exception 'Venta no encontrada';
  end if;
  if v_venta.anulada then
    raise exception 'La venta ya fue anulada';
  end if;
  if v_venta.created_at::date <> current_date then
    raise exception 'Solo se anulan ventas del dia de hoy';
  end if;

  for v_item in
    select * from public.venta_items where venta_id = v_venta.id
  loop
    perform public.aplicar_movimiento(
      v_item.producto_id,
      v_item.cantidad,
      'anulacion',
      coalesce(p_motivo, 'Venta anulada')
    );
  end loop;

  update public.caja
  set ventas_total = ventas_total - v_venta.subtotal
  where id = v_venta.caja_id;

update public.ventas
  set anulada = true,
      anulada_por = auth.uid(),
      anulada_at = now(),
      motivo_anulacion = p_motivo
  where id = v_venta.id;
end;
$$;

-- -------------------- BLOQUE 7 · EDITAR PRODUCTO --------------------

create or replace function public.actualizar_producto(
  p_producto_id uuid,
  p_nombre text,
  p_descripcion text default null,
  p_categoria_slug text default 'res',
  p_modo_venta public.modo_venta default 'unit',
  p_medida text default null,
  p_precio numeric(12, 2) default 0,
  p_precio_compra numeric(12, 2) default null,
  p_imagen_url text default null,
  p_stock_minimo numeric(10, 3) default null,
  p_ubicacion text default null,
  p_activo boolean default true
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_categoria_id uuid;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede editar productos';
  end if;
  if p_producto_id is null then
    raise exception 'Producto invalido';
  end if;
  if p_nombre is null or trim(p_nombre) = '' then
    raise exception 'El nombre es obligatorio';
  end if;
  if exists (
    select 1 from public.products
    where lower(nombre) = lower(trim(p_nombre)) and activo and id <> p_producto_id
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

  select id into v_categoria_id
  from public.categories
  where slug = p_categoria_slug;
  if not found then
    raise exception 'Categoria invalida';
  end if;

  update public.products
  set nombre = trim(p_nombre),
      descripcion = nullif(trim(coalesce(p_descripcion, '')), ''),
      categoria_id = v_categoria_id,
      modo_venta = p_modo_venta,
      medida = p_medida,
      precio = p_precio,
      precio_compra = p_precio_compra,
      imagen_url = nullif(trim(coalesce(p_imagen_url, '')), ''),
      activo = p_activo
  where id = p_producto_id;

  if not found then
    raise exception 'Producto no encontrado';
  end if;

  update public.inventory
  set stock_minimo = coalesce(p_stock_minimo, stock_minimo),
      ubicacion = nullif(trim(coalesce(p_ubicacion, '')), '')
  where producto_id = p_producto_id;
end;
$$;

create or replace function public.abrir_caja(p_efectivo_inicial numeric(12, 2) default 0) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe abre la caja';
  end if;

  select id into v_id
  from public.caja
  where fecha = current_date
  limit 1;

  if not found then
    insert into public.caja (fecha, efectivo_inicial, creada_por)
    values (current_date, coalesce(p_efectivo_inicial, 0), auth.uid())
    returning id into v_id;
    return v_id;
  end if;

  if exists (select 1 from public.caja where id = v_id and abierta) then
    raise exception 'La caja de hoy ya fue abierta';
  end if;

  update public.caja
  set abierta = true,
      cerrada_at = null,
      cerrada_por = null,
      efectivo_final = null
  where id = v_id;

  return v_id;
end;
$$;
-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 9
--  Métodos de pago y clientes.
--  - clientes con saldo (lo que deben) + abonos.
--  - ventas con pagos por método: efectivo, tarjeta, transferencia.
--  - venta "a crédito": se suma al saldo del cliente.
--  - caja separa efectivo (físico) de lo digital.
--  Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

do $$ begin
  create type public.metodo_pago as enum ('efectivo', 'tarjeta', 'transferencia');
exception when duplicate_object then null;
end $$;

-- -------------------- CLIENTES --------------------

create table if not exists public.clientes (
  id uuid default gen_random_uuid() primary key,
  nombre text not null,
  telefono text,
  saldo numeric(12, 2) not null default 0 check (saldo >= 0),
  creado_por uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

alter table public.clientes enable row level security;

drop policy if exists "Lectura de clientes" on public.clientes;
create policy "Lectura de clientes"
  on public.clientes for select to authenticated using (true);
drop policy if exists "Gestion de clientes" on public.clientes;
create policy "Gestion de clientes"
  on public.clientes for all to authenticated using (true) with check (true);

create index if not exists idx_clientes_nombre on public.clientes (lower(nombre) text_pattern_ops);

-- -------------------- PAGOS Y ABONOS --------------------

create table if not exists public.pagos (
  id uuid default gen_random_uuid() primary key,
  venta_id uuid not null references public.ventas on delete cascade,
  metodo public.metodo_pago not null,
  monto numeric(12, 2) not null check (monto > 0),
  creado_por uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

alter table public.pagos enable row level security;

drop policy if exists "Lectura de pagos" on public.pagos;
create policy "Lectura de pagos"
  on public.pagos for select to authenticated using (true);
drop policy if exists "Gestion de pagos" on public.pagos;
create policy "Gestion de pagos"
  on public.pagos for all to authenticated using (true) with check (true);

create index if not exists idx_pagos_venta on public.pagos (venta_id);

create table if not exists public.abonos (
  id uuid default gen_random_uuid() primary key,
  cliente_id uuid not null references public.clientes on delete restrict,
  monto numeric(12, 2) not null check (monto > 0),
  metodo public.metodo_pago not null,
  nota text,
  creado_por uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

alter table public.abonos enable row level security;

drop policy if exists "Lectura de abonos" on public.abonos;
create policy "Lectura de abonos"
  on public.abonos for select to authenticated using (true);
drop policy if exists "Gestion de abonos" on public.abonos;
create policy "Gestion de abonos"
  on public.abonos for all to authenticated using (true) with check (true);

create index if not exists idx_abonos_cliente on public.abonos (cliente_id);

-- -------------------- VENTAS A CRÉDITO --------------------

alter table public.ventas add column if not exists cliente_id uuid references public.clientes on delete set null;
create index if not exists idx_ventas_cliente on public.ventas (cliente_id);

-- -------------------- CAJA: EFECTIVO vs DIGITAL --------------------

alter table public.caja
  add column if not exists efectivo_cobrado numeric(12, 2) not null default 0,
  add column if not exists digital_cobrado numeric(12, 2) not null default 0;

-- -------------------- RPC CLIENTES --------------------

create or replace function public.registrar_cliente(
  p_nombre text,
  p_telefono text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if p_nombre is null or trim(p_nombre) = '' then
    raise exception 'El nombre del cliente es obligatorio';
  end if;

  insert into public.clientes (nombre, telefono, creado_por)
  values (trim(p_nombre), nullif(trim(coalesce(p_telefono, '')), ''), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.listar_clientes() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  select coalesce(jsonb_agg(x order by x.nombre), '[]'::jsonb)
  into v_resultado
  from (
    select id, nombre, telefono, saldo, created_at
    from public.clientes
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.ventas_cliente(p_cliente_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      v.id,
      v.subtotal,
      v.anulada,
      v.motivo_anulacion,
      v.created_at,
      coalesce(pr.nombre, 'Desconocido') as carnicero,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('nombre', i.nombre, 'cantidad', i.cantidad,
                             'medida', i.medida, 'precio', i.precio, 'subtotal', i.subtotal)
        )
        from public.venta_items i
        where i.venta_id = v.id
      ), '[]'::jsonb) as articulos,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('metodo', p.metodo, 'monto', p.monto)
        )
        from public.pagos p
        where p.venta_id = v.id
      ), '[]'::jsonb) as pagos
    from public.ventas v
    left join public.profiles pr on pr.id = v.creada_por
    where v.cliente_id = p_cliente_id
    order by v.created_at desc
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.abonos_cliente(p_cliente_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb)
  into v_resultado
  from (
    select id, monto, metodo, nota, created_at
    from public.abonos
    where cliente_id = p_cliente_id
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.abonar_cuenta(
  p_cliente_id uuid,
  p_monto numeric(12, 2),
  p_metodo public.metodo_pago default 'efectivo'
) returns numeric(12, 2)
language plpgsql security definer set search_path = public as $$
declare
  v_saldo numeric(12, 2);
  v_caja public.caja%rowtype;
begin
  if p_cliente_id is null then
    raise exception 'Cliente invalido';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El abono debe ser mayor a cero';
  end if;

  select saldo into v_saldo
  from public.clientes
  where id = p_cliente_id
  for update;

  if not found then
    raise exception 'Cliente no encontrado';
  end if;
  if p_monto > v_saldo then
    raise exception 'El abono supera la deuda del cliente';
  end if;

  select * into v_caja
  from public.caja
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    raise exception 'No hay caja abierta; ábrela antes de registrar el abono';
  end if;

  update public.clientes
  set saldo = saldo - p_monto
  where id = p_cliente_id
  returning saldo into v_saldo;

  insert into public.abonos (cliente_id, monto, metodo, creado_por)
  values (p_cliente_id, p_monto, p_metodo, auth.uid());

  if p_metodo = 'efectivo' then
    update public.caja
    set efectivo_cobrado = efectivo_cobrado + p_monto
    where id = v_caja.id;
  else
    update public.caja
    set digital_cobrado = digital_cobrado + p_monto
    where id = v_caja.id;
  end if;

  return v_saldo;
end;
$$;

-- -------------------- VENTA CON MÉTODOS --------------------

create or replace function public.registrar_venta(
  p_items jsonb,
  p_pagos jsonb default '[]'::jsonb,
  p_cliente_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_caja public.caja%rowtype;
  v_item jsonb;
  v_producto record;
  v_cantidad numeric(10, 3);
  v_subtotal numeric(12, 2);
  v_total numeric(12, 2) := 0;
  v_venta_id uuid;
  v_pago jsonb;
  v_pagado numeric(12, 2) := 0;
  v_efectivo_total numeric(12, 2) := 0;
  v_digital_total numeric(12, 2) := 0;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene articulos';
  end if;

  if p_cliente_id is null and (p_pagos is null or jsonb_array_length(p_pagos) = 0) then
    raise exception 'Indica un metodo de pago o vende a credito';
  end if;

  if p_pagos is not null then
    for v_pago in select * from jsonb_array_elements(p_pagos) loop
      if (v_pago->>'metodo') not in ('efectivo', 'tarjeta', 'transferencia') then
        raise exception 'Metodo de pago invalido';
      end if;
      if (v_pago->>'monto')::numeric(12, 2) <= 0 then
        raise exception 'El pago debe ser mayor a cero';
      end if;
      if (v_pago->>'metodo') = 'transferencia'
         and (v_pago->>'monto')::numeric(12, 2) < 1 then
        raise exception 'La transferencia minima es de $1';
      end if;
      v_pagado := v_pagado + (v_pago->>'monto')::numeric(12, 2);
    end loop;
  end if;

  select * into v_caja
  from public.caja
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    raise exception 'No hay caja abierta; ábrela antes de cobrar';
  end if;

  insert into public.ventas (caja_id, subtotal, creada_por, cliente_id)
  values (v_caja.id, 0, auth.uid(), p_cliente_id)
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

  if p_cliente_id is not null then
    if v_pagado > 0 then
      raise exception 'Una venta a credito no lleva pagos; registra un abono aparte a la cuenta';
    end if;
    update public.clientes set saldo = saldo + v_total where id = p_cliente_id;
  else
    if v_pagado <> v_total then
      raise exception 'La suma de los pagos no coincide con el total de la venta';
    end if;
    for v_pago in select * from jsonb_array_elements(p_pagos) loop
      insert into public.pagos (venta_id, metodo, monto, creado_por)
      values (v_venta_id, (v_pago->>'metodo')::public.metodo_pago,
              (v_pago->>'monto')::numeric(12, 2), auth.uid());
      if (v_pago->>'metodo') = 'efectivo' then
        v_efectivo_total := v_efectivo_total + (v_pago->>'monto')::numeric(12, 2);
      else
        v_digital_total := v_digital_total + (v_pago->>'monto')::numeric(12, 2);
      end if;
    end loop;
    update public.caja
    set ventas_total = ventas_total + v_total,
        efectivo_cobrado = efectivo_cobrado + v_efectivo_total,
        digital_cobrado = digital_cobrado + v_digital_total
    where id = v_caja.id;
  end if;

  update public.ventas set subtotal = v_total where id = v_venta_id;

  return v_venta_id;
end;
$$;

-- -------------------- VENTAS DEL DÍA (con métodos) --------------------

create or replace function public.ventas_del_dia(p_caja_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      v.id,
      v.subtotal,
      v.anulada,
      v.cliente_id,
      coalesce(cl.nombre, null) as cliente,
      v.created_at,
      coalesce(pr.nombre, 'Desconocido') as carnicero,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('nombre', i.nombre, 'cantidad', i.cantidad, 'subtotal', i.subtotal)
        )
        from public.venta_items i
        where i.venta_id = v.id
      ), '[]'::jsonb) as articulos,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('metodo', pg.metodo, 'monto', pg.monto)
        )
        from public.pagos pg
        where pg.venta_id = v.id
      ), '[]'::jsonb) as pagos
    from public.ventas v
    left join public.profiles pr on pr.id = v.creada_por
    left join public.clientes cl on cl.id = v.cliente_id
    where v.caja_id = p_caja_id
  ) x;
  return v_resultado;
end;
$$;

-- -------------------- ANULAR (coherente con pagos y crédito) --------------------

create or replace function public.anular_venta(p_venta_id uuid, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_venta record;
  v_item record;
  v_efectivo numeric(12, 2) := 0;
  v_digital numeric(12, 2) := 0;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede anular ventas';
  end if;
  if p_venta_id is null then
    raise exception 'Venta invalida';
  end if;

  select * into v_venta
  from public.ventas
  where id = p_venta_id
  for update;

  if not found then
    raise exception 'Venta no encontrada';
  end if;
  if v_venta.anulada then
    raise exception 'La venta ya fue anulada';
  end if;
  if v_venta.created_at::date <> current_date then
    raise exception 'Solo se anulan ventas del día de hoy';
  end if;

  if v_venta.cliente_id is not null then
    update public.clientes
    set saldo = saldo - v_venta.subtotal
    where id = v_venta.cliente_id;
  else
    select coalesce(sum(monto) filter (where metodo = 'efectivo'), 0)
    into v_efectivo
    from public.pagos
    where venta_id = v_venta.id;

    select coalesce(sum(monto) filter (where metodo <> 'efectivo'), 0)
    into v_digital
    from public.pagos
    where venta_id = v_venta.id;

    update public.caja
    set ventas_total = ventas_total - v_venta.subtotal,
        efectivo_cobrado = efectivo_cobrado - v_efectivo,
        digital_cobrado = digital_cobrado - v_digital
    where id = v_venta.caja_id;
  end if;

  for v_item in
    select * from public.venta_items where venta_id = v_venta.id
  loop
    perform public.aplicar_movimiento(
      v_item.producto_id,
      v_item.cantidad,
      'anulacion',
      coalesce(p_motivo, 'Venta anulada')
    );
  end loop;

  update public.ventas
  set anulada = true,
      anulada_por = auth.uid(),
      anulada_at = now(),
      motivo_anulacion = p_motivo
  where id = v_venta.id;
end;
$$;

-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 10
--  Reportes (solo jefe).
--  - resumen del período (facturado, cobrado por método, crédito, anulado).
--  - ventas por día, por carnicero, por método de pago.
--  - top productos y detalle de ventas del período (para auditoría/impresión).
--  Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

create or replace function public.reporte_resumen(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ver reportes';
  end if;

  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'ventas', count(*) filter (where not anulada),
    'facturado', coalesce(sum(subtotal) filter (where not anulada), 0),
    'a_credito', coalesce(sum(subtotal) filter (where not anulada and cliente_id is not null), 0),
    'anulado', coalesce(sum(subtotal) filter (where anulada), 0),
    'efectivo', coalesce((
      select sum(p.monto)
      from public.pagos p
      join public.ventas vv on vv.id = p.venta_id
      where vv.created_at::date between p_desde and p_hasta
        and not vv.anulada and p.metodo = 'efectivo'
    ), 0),
    'tarjeta', coalesce((
      select sum(p.monto)
      from public.pagos p
      join public.ventas vv on vv.id = p.venta_id
      where vv.created_at::date between p_desde and p_hasta
        and not vv.anulada and p.metodo = 'tarjeta'
    ), 0),
    'transferencia', coalesce((
      select sum(p.monto)
      from public.pagos p
      join public.ventas vv on vv.id = p.venta_id
      where vv.created_at::date between p_desde and p_hasta
        and not vv.anulada and p.metodo = 'transferencia'
    ), 0),
    'abonos', coalesce((
      select sum(monto) from public.abonos
      where created_at::date between p_desde and p_hasta
    ), 0)
  )
  into v_resultado
  from public.ventas
  where created_at::date between p_desde and p_hasta;

  return v_resultado;
end;
$$;

create or replace function public.reporte_por_dia(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ver reportes';
  end if;

  select coalesce(jsonb_agg(x order by x.fecha), '[]'::jsonb)
  into v_resultado
  from (
    select
      d.fecha,
      d.ventas,
      d.facturado,
      d.a_credito,
      d.anulado,
      coalesce((
        select sum(p.monto) from public.pagos p
        join public.ventas vv on vv.id = p.venta_id
        where vv.created_at::date = d.fecha and not vv.anulada and p.metodo = 'efectivo'
      ), 0) as efectivo,
      coalesce((
        select sum(p.monto) from public.pagos p
        join public.ventas vv on vv.id = p.venta_id
        where vv.created_at::date = d.fecha and not vv.anulada and p.metodo <> 'efectivo'
      ), 0) as digital
    from (
      select
        created_at::date as fecha,
        count(*) filter (where not anulada) as ventas,
        sum(subtotal) filter (where not anulada) as facturado,
        sum(subtotal) filter (where not anulada and cliente_id is not null) as a_credito,
        sum(subtotal) filter (where anulada) as anulado
      from public.ventas
      where created_at::date between p_desde and p_hasta
      group by created_at::date
    ) d
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.reporte_por_carnicero(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ver reportes';
  end if;

  select coalesce(jsonb_agg(x order by x.facturado desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      coalesce(pr.nombre, 'Desconocido') as carnicero,
      count(*) filter (where not v.anulada) as ventas,
      sum(v.subtotal) filter (where not v.anulada and v.cliente_id is null) as cobrado,
      sum(v.subtotal) filter (where not v.anulada and v.cliente_id is not null) as a_credito,
      sum(v.subtotal) filter (where not v.anulada) as facturado
    from public.ventas v
    left join public.profiles pr on pr.id = v.creada_por
    where v.created_at::date between p_desde and p_hasta
    group by pr.id, pr.nombre
    order by facturado desc
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.reporte_metodos(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ver reportes';
  end if;

select coalesce(jsonb_agg(x), '[]'::jsonb)
  into v_resultado
  from (
    select metodo, monto
    from (
      select 'efectivo' as metodo, coalesce(sum(p.monto), 0) as monto
      from public.pagos p
      join public.ventas vv on vv.id = p.venta_id
      where vv.created_at::date between p_desde and p_hasta
        and not vv.anulada and p.metodo = 'efectivo'
      union all
      select 'tarjeta', coalesce(sum(p.monto), 0)
      from public.pagos p
      join public.ventas vv on vv.id = p.venta_id
      where vv.created_at::date between p_desde and p_hasta
        and not vv.anulada and p.metodo = 'tarjeta'
      union all
      select 'transferencia', coalesce(sum(p.monto), 0)
      from public.pagos p
      join public.ventas vv on vv.id = p.venta_id
      where vv.created_at::date between p_desde and p_hasta
        and not vv.anulada and p.metodo = 'transferencia'
      union all
      select 'a_credito', coalesce(sum(subtotal), 0)
      from public.ventas
      where created_at::date between p_desde and p_hasta
        and not anulada and cliente_id is not null
      union all
      select 'abonos', coalesce(sum(monto), 0)
      from public.abonos
      where created_at::date between p_desde and p_hasta
    ) x
    where monto <> 0
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.reporte_top_productos(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ver reportes';
  end if;

  select coalesce(jsonb_agg(x order by x.total desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      i.nombre,
      max(i.medida) as medida,
      sum(i.cantidad) as cantidad,
      sum(i.subtotal) as total
    from public.venta_items i
    join public.ventas v on v.id = i.venta_id
    where v.created_at::date between p_desde and p_hasta and not v.anulada
    group by i.nombre
    order by coalesce(sum(i.subtotal), 0) desc
    limit 12
  ) x;
  return v_resultado;
end;
$$;

create or replace function public.reporte_ventas(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede ver reportes';
  end if;

  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      v.id,
      v.subtotal,
      v.anulada,
      v.motivo_anulacion,
      v.cliente_id,
      coalesce(cl.nombre, null) as cliente,
      v.created_at,
      coalesce(pr.nombre, 'Desconocido') as carnicero,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('nombre', i.nombre, 'cantidad', i.cantidad,
                             'medida', i.medida, 'precio', i.precio, 'subtotal', i.subtotal)
        )
        from public.venta_items i
        where i.venta_id = v.id
      ), '[]'::jsonb) as articulos,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('metodo', pg.metodo, 'monto', pg.monto)
        )
        from public.pagos pg
        where pg.venta_id = v.id
      ), '[]'::jsonb) as pagos
    from public.ventas v
    left join public.profiles pr on pr.id = v.creada_por
    left join public.clientes cl on cl.id = v.cliente_id
    where v.created_at::date between p_desde and p_hasta
  ) x;
  return v_resultado;
end;
$$;-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 11
--  Acceso por roles en pantalla.
--  - caja_vivo(): estado de la caja abierta para cualquier
--    empleado autenticado (saben si pueden cobrar). El
--    historial de turnos y el resto de "caja" siguen siendo
--    solo del jefe (políticas RLS existentes).
--  Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

create or replace function public.caja_vivo()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_caja public.caja%rowtype;
begin
  select * into v_caja
  from public.caja
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_caja.id,
    'fecha', to_char(v_caja.fecha, 'YYYY-MM-DD'),
    'abierta', v_caja.abierta,
    'efectivo_inicial', v_caja.efectivo_inicial,
    'ventas_total', v_caja.ventas_total,
    'efectivo_cobrado', coalesce(v_caja.efectivo_cobrado, 0),
    'digital_cobrado', coalesce(v_caja.digital_cobrado, 0),
    'abierta_at', v_caja.abierta_at,
    'cerrada_at', v_caja.cerrada_at,
    'efectivo_final', v_caja.efectivo_final
  );
end;
$$;
-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 12
--  La caja la abren y cierran todos los empleados.
--  - abrir_caja / cerrar_caja: ya no exigen rol de jefe,
--    por si el jefe no asiste un día.
--  - caja_vivo(): devuelve el turno en curso; si no hay turno
--    abierto, el último del día (para ver el cuadre o reabrir).
--  - Anular ventas y el historial de caja siguen siendo del jefe.
--  Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

create or replace function public.abrir_caja(
  p_efectivo_inicial numeric(12, 2) default 0
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if exists (select 1 from public.caja where abierta) then
    raise exception 'Ya hay una caja abierta; ciérrala antes de abrir otra';
  end if;

  insert into public.caja (fecha, efectivo_inicial, creada_por)
  values (current_date, coalesce(p_efectivo_inicial, 0), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.cerrar_caja(
  p_efectivo_final numeric(12, 2)
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_caja record;
begin
  select * into v_caja
  from public.caja
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    raise exception 'No hay caja abierta para cerrar';
  end if;

  update public.caja
  set abierta = false,
      cerrada_at = now(),
      cerrada_por = auth.uid(),
      efectivo_final = p_efectivo_final
  where id = v_caja.id;
end;
$$;

create or replace function public.caja_vivo()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_caja public.caja%rowtype;
begin
  select * into v_caja
  from public.caja
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    select * into v_caja
    from public.caja
    where fecha = current_date
    order by abierta_at desc
    limit 1;
  end if;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_caja.id,
    'fecha', to_char(v_caja.fecha, 'YYYY-MM-DD'),
    'abierta', v_caja.abierta,
    'efectivo_inicial', v_caja.efectivo_inicial,
    'ventas_total', v_caja.ventas_total,
    'efectivo_cobrado', coalesce(v_caja.efectivo_cobrado, 0),
    'digital_cobrado', coalesce(v_caja.digital_cobrado, 0),
    'abierta_at', v_caja.abierta_at,
    'cerrada_at', v_caja.cerrada_at,
    'efectivo_final', v_caja.efectivo_final
  );
end;
$$;
-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 13
--  Recibo de venta.
--  - Guarda el vuelto entregado y el efectivo recibido para
--    poder reimprimir el recibo de cualquier venta.
--  - registrar_venta ahora acepta p_vuelto.
--  - ventas_del_dia incluye vuelto, efectivo_recibido y los
--    artículos con medida/precio.
--  Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

alter table public.ventas add column if not exists vuelto numeric(12, 2) not null default 0;
alter table public.ventas add column if not exists efectivo_recibido numeric(12, 2);

create or replace function public.registrar_venta(
  p_items jsonb,
  p_pagos jsonb default '[]'::jsonb,
  p_cliente_id uuid default null,
  p_vuelto numeric(12, 2) default 0
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_caja public.caja%rowtype;
  v_item jsonb;
  v_producto record;
  v_cantidad numeric(10, 3);
  v_subtotal numeric(12, 2);
  v_total numeric(12, 2) := 0;
  v_venta_id uuid;
  v_pago jsonb;
  v_pagado numeric(12, 2) := 0;
  v_efectivo_total numeric(12, 2) := 0;
  v_digital_total numeric(12, 2) := 0;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene articulos';
  end if;

  if p_cliente_id is null and (p_pagos is null or jsonb_array_length(p_pagos) = 0) then
    raise exception 'Indica un metodo de pago o vende a credito';
  end if;

  if p_pagos is not null then
    for v_pago in select * from jsonb_array_elements(p_pagos) loop
      if (v_pago->>'metodo') not in ('efectivo', 'tarjeta', 'transferencia') then
        raise exception 'Metodo de pago invalido';
      end if;
      if (v_pago->>'monto')::numeric(12, 2) <= 0 then
        raise exception 'El pago debe ser mayor a cero';
      end if;
      if (v_pago->>'metodo') = 'transferencia'
         and (v_pago->>'monto')::numeric(12, 2) < 1 then
        raise exception 'La transferencia minima es de $1';
      end if;
      v_pagado := v_pagado + (v_pago->>'monto')::numeric(12, 2);
      if (v_pago->>'metodo') = 'efectivo' then
        v_efectivo_total := v_efectivo_total + (v_pago->>'monto')::numeric(12, 2);
      else
        v_digital_total := v_digital_total + (v_pago->>'monto')::numeric(12, 2);
      end if;
    end loop;
  end if;

  select * into v_caja
  from public.caja
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    raise exception 'No hay caja abierta; ábrela antes de cobrar';
  end if;

  insert into public.ventas (caja_id, subtotal, creada_por, cliente_id, vuelto)
  values (v_caja.id, 0, auth.uid(), p_cliente_id, coalesce(p_vuelto, 0))
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

  if p_cliente_id is not null then
    if v_pagado > 0 then
      raise exception 'Una venta a credito no lleva pagos; registra un abono aparte a la cuenta';
    end if;
    update public.clientes set saldo = saldo + v_total where id = p_cliente_id;
  else
    if v_pagado <> v_total then
      raise exception 'La suma de los pagos no coincide con el total de la venta';
    end if;
    for v_pago in select * from jsonb_array_elements(p_pagos) loop
      insert into public.pagos (venta_id, metodo, monto, creado_por)
      values (v_venta_id, (v_pago->>'metodo')::public.metodo_pago,
              (v_pago->>'monto')::numeric(12, 2), auth.uid());
    end loop;
    update public.caja
    set ventas_total = ventas_total + v_total,
        efectivo_cobrado = efectivo_cobrado + v_efectivo_total,
        digital_cobrado = digital_cobrado + v_digital_total
    where id = v_caja.id;
  end if;

  update public.ventas
  set subtotal = v_total,
      efectivo_recibido = case when v_efectivo_total > 0 then v_efectivo_total + coalesce(p_vuelto, 0) else null end
  where id = v_venta_id;

  return v_venta_id;
end;
$$;

-- -------------------- VENTAS DEL DÍA (con datos de recibo) --------------------

create or replace function public.ventas_del_dia(p_caja_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resultado jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb)
  into v_resultado
  from (
    select
      v.id,
      v.subtotal,
      v.anulada,
      v.motivo_anulacion,
      v.vuelto,
      v.efectivo_recibido,
      v.cliente_id,
      coalesce(cl.nombre, null) as cliente,
      v.created_at,
      coalesce(pr.nombre, 'Desconocido') as carnicero,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('nombre', i.nombre, 'cantidad', i.cantidad,
                             'medida', i.medida, 'precio', i.precio, 'subtotal', i.subtotal)
        )
        from public.venta_items i
        where i.venta_id = v.id
      ), '[]'::jsonb) as articulos,
      coalesce((
        select jsonb_agg(
          jsonb_build_object('metodo', pg.metodo, 'monto', pg.monto)
        )
        from public.pagos pg
        where pg.venta_id = v.id
      ), '[]'::jsonb) as pagos
    from public.ventas v
    left join public.profiles pr on pr.id = v.creada_por
    left join public.clientes cl on cl.id = v.cliente_id
    where v.caja_id = p_caja_id
  ) x;
  return v_resultado;
end;
$$;
-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 14
--  Edición de producto con ajuste de existencia actual.
--  - actualizar_producto acepta p_stock_actual; si es distinto
--    de lo que hay en inventario, ajusta la existencia y la
--    registra como movimiento 'ajuste' ("Ajuste desde inventario").
--  Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

create or replace function public.actualizar_producto(
  p_producto_id uuid,
  p_nombre text,
  p_descripcion text default null,
  p_categoria_slug text default 'res',
  p_modo_venta public.modo_venta default 'unit',
  p_medida text default null,
  p_precio numeric(12, 2) default 0,
  p_precio_compra numeric(12, 2) default null,
  p_imagen_url text default null,
  p_stock_minimo numeric(10, 3) default null,
  p_ubicacion text default null,
  p_activo boolean default true,
  p_stock_actual numeric(10, 3) default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_categoria_id uuid;
  v_cantidad_actual numeric(10, 3);
begin
  if not public.es_jefe() then
    raise exception 'Solo el jefe puede editar productos';
  end if;
  if p_producto_id is null then
    raise exception 'Producto invalido';
  end if;
  if p_nombre is null or trim(p_nombre) = '' then
    raise exception 'El nombre es obligatorio';
  end if;
  if exists (
    select 1 from public.products
    where lower(nombre) = lower(trim(p_nombre)) and activo and id <> p_producto_id
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

  select id into v_categoria_id
  from public.categories
  where slug = p_categoria_slug;
  if not found then
    raise exception 'Categoria invalida';
  end if;

  update public.products
  set nombre = trim(p_nombre),
      descripcion = nullif(trim(coalesce(p_descripcion, '')), ''),
      categoria_id = v_categoria_id,
      modo_venta = p_modo_venta,
      medida = p_medida,
      precio = p_precio,
      precio_compra = p_precio_compra,
      imagen_url = nullif(trim(coalesce(p_imagen_url, '')), ''),
      activo = p_activo
  where id = p_producto_id;

  if not found then
    raise exception 'Producto no encontrado';
  end if;

  update public.inventory
  set stock_minimo = coalesce(p_stock_minimo, stock_minimo),
      ubicacion = nullif(trim(coalesce(p_ubicacion, '')), '')
  where producto_id = p_producto_id;

  if p_stock_actual is not null then
    if p_stock_actual < 0 then
      raise exception 'La existencia no puede quedar negativa';
    end if;
    select cantidad into v_cantidad_actual
    from public.inventory
    where producto_id = p_producto_id;
    if v_cantidad_actual is not null and v_cantidad_actual <> p_stock_actual then
      perform public.aplicar_movimiento(
        p_producto_id,
        p_stock_actual - v_cantidad_actual,
        'ajuste',
        'Ajuste desde inventario'
      );
    end if;
  end if;
end;
$$;
