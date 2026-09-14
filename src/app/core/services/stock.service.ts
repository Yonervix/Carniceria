import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import type {
  ItemDespostePayload,
  MovimientoReciente,
  ResultadoOperacion,
} from '../modelos/operaciones';

@Injectable({ providedIn: 'root' })
export class StockService {
  private readonly supabase = inject(SupabaseService);
  private readonly client: SupabaseClient | null = this.supabase.client;

  readonly movimientos = signal<MovimientoReciente[]>([]);
  readonly cargandoMovimientos = signal(false);

  async cargarMovimientos(): Promise<void> {
    if (!this.client) return;
    this.cargandoMovimientos.set(true);
    const { data, error } = await this.client
      .from('inventory_movements')
      .select('id, concepto, cambio, saldo, nota, created_at, products(nombre)')
      .order('created_at', { ascending: false })
      .limit(12);
    if (error) {
      this.cargandoMovimientos.set(false);
      return;
    }
    const filas = (data ?? []) as Array<{
      id: number;
      concepto: string;
      cambio: number;
      saldo: number;
      nota: string | null;
      created_at: string;
      products: Array<{ nombre: string }> | null;
    }>;
    this.movimientos.set(
      filas.map((m) => ({
        id: m.id,
        concepto: m.concepto,
        cambio: m.cambio,
        saldo: m.saldo,
        nota: m.nota,
        created_at: m.created_at,
        nombre: m.products?.[0]?.nombre ?? 'Producto',
      })),
    );
    this.cargandoMovimientos.set(false);
  }

  async merma(
    productoId: string,
    cantidad: number,
    nota: string | null,
  ): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('registrar_merma', {
      p_producto_id: productoId,
      p_cantidad: cantidad,
      p_nota: nota,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.cargarMovimientos();
    return { ok: true, error: null };
  }

  async desposte(
    origenId: string,
    pesoOrigen: number,
    destinos: ItemDespostePayload[],
    nota: string | null,
  ): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('registrar_desposte', {
      p_origen_id: origenId,
      p_peso_origen: pesoOrigen,
      p_destinos: destinos,
      p_nota: nota,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.cargarMovimientos();
    return { ok: true, error: null };
  }

  private legible(mensaje: string): string {
    if (/negativa|existencia|insuficiente/i.test(mensaje)) return 'Stock insuficiente';
    if (/suma de destinos/i.test(mensaje)) return 'La suma de destinos supera el peso de origen';
    if (/no encontrado/i.test(mensaje)) return 'Producto no encontrado';
    if (/jefe/i.test(mensaje)) return 'Solo el jefe puede hacer esto';
    return mensaje;
  }
}