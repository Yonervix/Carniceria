-- ============================================================
--  CORTE · Carnicería boutique · BLOQUE 6
--  Reabrir la caja del día después de cerrarla.
--  Idempotente: se puede re-ejecutar completo en SQL Editor.
-- ============================================================

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