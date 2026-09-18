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