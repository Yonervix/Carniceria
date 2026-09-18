import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import type {
  AbonoCliente,
  CajaEstado,
  Cliente,
  ItemVentaPayload,
  MetodoPago,
  PagoVenta,
  ResultadoOperacion,
  TurnoCajaHistorial,
  VentaCliente,
  VentaHistorial,
} from '../modelos/operaciones';

@Injectable({ providedIn: 'root' })
export class CajaService {
  private readonly supabase = inject(SupabaseService);
  private readonly client: SupabaseClient | null = this.supabase.client;

  readonly estado = signal<CajaEstado | null>(null);
  readonly ventasHoy = signal<VentaHistorial[]>([]);
  readonly historial = signal<TurnoCajaHistorial[]>([]);
  readonly cargando = signal(false);
  readonly sinBackend = signal(false);
  readonly error = signal('');

  constructor() {
    if (!this.client) {
      this.sinBackend.set(true);
      return;
    }
    void this.sincronizar();
    this.suscribir();
  }

  get conectado(): boolean {
    return this.client !== null;
  }

  async sincronizar(): Promise<void> {
    if (!this.client) return;
    this.cargando.set(true);
    const { data, error } = await this.client.rpc('caja_vivo');
    if (error) {
      this.error.set(error.message);
      this.cargando.set(false);
      return;
    }
    const caja = (data as CajaEstado | null) ?? null;
    this.estado.set(caja);
    this.error.set('');
    this.cargando.set(false);
    if (caja) void this.cargarVentas(caja.id);
  }

  async cargarVentas(cajaId: string): Promise<void> {
    if (!this.client) return;
    const { data, error } = await this.client.rpc('ventas_del_dia', {
      p_caja_id: cajaId,
    });
    if (error) return;
    const lista = (data as VentaHistorial[] | null) ?? [];
    this.ventasHoy.set(lista.map((v) => normalizarVenta(v)));
  }

  async cargarHistorial(): Promise<void> {
    if (!this.client) return;
    const { data } = await this.client
      .from('caja')
      .select('id, fecha, abierta, efectivo_inicial, ventas_total, efectivo_cobrado, digital_cobrado, abierta_at, cerrada_at, efectivo_final')
      .order('fecha', { ascending: false })
      .limit(90);
    this.historial.set(((data ?? []) as TurnoCajaHistorial[]).map((t) => ({
      ...t,
      efectivo_inicial: Number(t.efectivo_inicial),
      ventas_total: Number(t.ventas_total),
      efectivo_cobrado: Number(t.efectivo_cobrado ?? 0),
      digital_cobrado: Number(t.digital_cobrado ?? 0),
      efectivo_final: t.efectivo_final !== null ? Number(t.efectivo_final) : null,
    })));
  }

  async ventasDeCaja(cajaId: string): Promise<VentaHistorial[]> {
    if (!this.client) return [];
    const { data, error } = await this.client.rpc('ventas_del_dia', {
      p_caja_id: cajaId,
    });
    if (error) return [];
    const lista = (data as VentaHistorial[] | null) ?? [];
    return lista.map((v) => normalizarVenta(v));
  }

  async anularVenta(ventaId: string, motivo?: string): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('anular_venta', {
      p_venta_id: ventaId,
      p_motivo: motivo || null,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.sincronizar();
    return { ok: true, error: null };
  }

  suscribir(): void {
    if (!this.client) return;
    this.client
      .channel('corte-caja-vivo')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'caja' },
        () => void this.sincronizar(),
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'ventas' },
        () => {
          const caja = this.estado();
          if (caja) void this.cargarVentas(caja.id);
        },
      )
      .subscribe();
  }

  async abrir(efectivoInicial: number): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('abrir_caja', {
      p_efectivo_inicial: efectivoInicial,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.sincronizar();
    return { ok: true, error: null };
  }

  async cerrar(efectivoFinal: number): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('cerrar_caja', {
      p_efectivo_final: efectivoFinal,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.sincronizar();
    return { ok: true, error: null };
  }

  async registrarVenta(
    items: ItemVentaPayload[],
    pagos?: PagoVenta[],
    clienteId?: string | null,
    vuelto = 0,
  ): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { data, error } = await this.client.rpc('registrar_venta', {
      p_items: items,
      p_pagos: pagos && pagos.length > 0 ? pagos : null,
      p_cliente_id: clienteId || null,
      p_vuelto: vuelto,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.sincronizar();
    return { ok: true, error: null, id: (data as string | null) ?? null };
  }

  async registrarCliente(nombre: string, telefono?: string): Promise<string | null> {
    if (!this.client) return null;
    const { data, error } = await this.client.rpc('registrar_cliente', {
      p_nombre: nombre,
      p_telefono: telefono || null,
    });
    if (error) return null;
    return (data as string | null) ?? null;
  }

  async abonarCuenta(
    clienteId: string,
    monto: number,
    metodo: MetodoPago = 'efectivo',
  ): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('abonar_cuenta', {
      p_cliente_id: clienteId,
      p_monto: monto,
      p_metodo: metodo,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.sincronizar();
    return { ok: true, error: null };
  }

  async listarClientes(): Promise<Cliente[]> {
    if (!this.client) return [];
    const { data, error } = await this.client.rpc('listar_clientes');
    if (error) return [];
    return ((data as Cliente[] | null) ?? []).map((c) => ({
      ...c,
      saldo: Number(c.saldo),
    }));
  }

  async ventasCliente(clienteId: string): Promise<VentaCliente[]> {
    if (!this.client) return [];
    const { data, error } = await this.client.rpc('ventas_cliente', {
      p_cliente_id: clienteId,
    });
    if (error) return [];
    return ((data as VentaCliente[] | null) ?? []).map((v) => ({
      ...v,
      subtotal: Number(v.subtotal),
      articulos: (v.articulos ?? []).map((a) => ({
        nombre: a.nombre,
        cantidad: Number(a.cantidad),
        medida: a.medida ?? undefined,
        precio: a.precio !== undefined && a.precio !== null ? Number(a.precio) : undefined,
        subtotal: Number(a.subtotal),
      })),
      pagos: (v.pagos ?? []).map((p) => ({ ...p, monto: Number(p.monto) })),
    }));
  }

  async abonosCliente(clienteId: string): Promise<AbonoCliente[]> {
    if (!this.client) return [];
    const { data, error } = await this.client.rpc('abonos_cliente', {
      p_cliente_id: clienteId,
    });
    if (error) return [];
    return ((data as AbonoCliente[] | null) ?? []).map((a) => ({
      ...a,
      monto: Number(a.monto),
    }));
  }

  private legible(mensaje: string): string {
    if (/No hay caja abierta/i.test(mensaje)) return 'Abre la caja antes de cobrar o abonar';
    if (/caja de hoy/i.test(mensaje)) return 'La caja de hoy ya fue abierta';
    if (/negativa|existencia/i.test(mensaje)) return 'Stock insuficiente para la venta';
    if (/caja abierta para cerrar/i.test(mensaje)) return 'No hay caja abierta para cerrar';
    if (/jefe puede anular/i.test(mensaje)) return 'Solo el jefe puede anular ventas';
    if (/ya fue anulada/i.test(mensaje)) return 'La venta ya fue anulada';
    if (/del dia de hoy/i.test(mensaje)) return 'Solo se anulan ventas del día de hoy';
    if (/jefe/i.test(mensaje)) return 'Solo el jefe puede hacer esto';
    if (/metodo de pago/i.test(mensaje)) return 'Elige un método de pago válido';
    if (/no coincide con el total/i.test(mensaje)) return 'La suma de los pagos no cubre el total';
    if (/minima/i.test(mensaje)) return 'La transferencia mínima es de $1';
    if (/supera la deuda/i.test(mensaje)) return 'El abono supera lo que debe el cliente';
    if (/no lleva pagos/i.test(mensaje)) return 'Una venta a crédito no lleva pagos';
    if (/vende a credito/i.test(mensaje)) return 'Elige un método de pago o el cliente';
    return mensaje;
  }
}

function normalizarVenta(v: VentaHistorial): VentaHistorial {
  return {
    ...v,
    articulos: v.articulos ?? [],
    pagos: (v.pagos ?? []).map((p) => ({ ...p, monto: Number(p.monto) })),
    subtotal: Number(v.subtotal),
    vuelto: Number(v.vuelto ?? 0),
    efectivo_recibido: v.efectivo_recibido !== null && v.efectivo_recibido !== undefined ? Number(v.efectivo_recibido) : null,
  };
}