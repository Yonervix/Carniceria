-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 5
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