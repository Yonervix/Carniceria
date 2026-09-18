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