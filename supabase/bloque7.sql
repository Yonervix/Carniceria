-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 7
--  Editar un producto desde inventario (solo jefe).
--  Idempotente: se puede re-ejecutar completo en SQL Editor.
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