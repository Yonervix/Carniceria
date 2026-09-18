-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 8
--  Varios turnos de caja por día.
--  - Se elimina la caja única por día (se puede abrir varias).
--  - Abrir siempre crea un turno NUEVO (solo uno abierto a la vez).
--  - Idempotente: se puede ejecutar sin importar cuántas veces.
-- ============================================================

alter table public.caja drop constraint if exists caja_unica_dia;

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
  if not public.es_jefe() then
    raise exception 'Solo el jefe cierra la caja';
  end if;

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
  where abierta
  order by abierta_at desc
  limit 1;

  if not found then
    raise exception 'No hay caja abierta; ábrela antes de cobrar';
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