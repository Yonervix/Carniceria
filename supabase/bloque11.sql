-- ============================================================
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