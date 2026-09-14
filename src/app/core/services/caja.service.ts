import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import type {
  CajaEstado,
  ItemVentaPayload,
  ResultadoOperacion,
  VentaRegistrada,
} from '../modelos/operaciones';

function fechaHoy(): string {
  return new Date().toISOString().slice(0, 10);
}

@Injectable({ providedIn: 'root' })
export class CajaService {
  private readonly supabase = inject(SupabaseService);
  private readonly client: SupabaseClient | null = this.supabase.client;

  readonly estado = signal<CajaEstado | null>(null);
  readonly ventasHoy = signal<VentaRegistrada[]>([]);
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
    const { data, error } = await this.client
      .from('caja')
      .select('*')
      .eq('fecha', fechaHoy())
      .order('abierta_at', { ascending: false })
      .limit(1)
      .maybeSingle();

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
    const { data, error } = await this.client
      .from('ventas')
      .select('id, caja_id, subtotal, created_at')
      .eq('caja_id', cajaId)
      .order('created_at', { ascending: false });
    if (error) return;
    this.ventasHoy.set((data ?? []) as VentaRegistrada[]);
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

  async registrarVenta(items: ItemVentaPayload[]): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('registrar_venta', { p_items: items });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.sincronizar();
    return { ok: true, error: null };
  }

  private legible(mensaje: string): string {
    if (/No hay caja abierta para el dia/i.test(mensaje)) return 'Abre la caja del día antes de cobrar';
    if (/caja de hoy/i.test(mensaje)) return 'La caja de hoy ya fue abierta';
    if (/negativa|existencia/i.test(mensaje)) return 'Stock insuficiente para la venta';
    if (/caja abierta para cerrar/i.test(mensaje)) return 'No hay caja abierta para cerrar';
    if (/jefe/i.test(mensaje)) return 'Solo el jefe puede hacer esto';
    return mensaje;
  }
}