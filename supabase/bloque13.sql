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