-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 4
--  Acceso y sesión. PE GAR EL CONTENIDO COMPLETO EN
--  Supabase → SQL Editor → Run. Es seguro re-ejecutarlo.
--  Incluye: perfiles endurecidos (nadie se auto-asigna jefe),
--  "reclamar jefe" (solo la primera cuenta) y alta de productos
--  desde la app (solo jefe).
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