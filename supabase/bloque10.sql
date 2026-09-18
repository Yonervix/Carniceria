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
$$;