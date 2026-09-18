import { Injectable, inject } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import type {
  FilaCarnicero,
  FilaDia,
  FilaMetodo,
  FilaTopProducto,
  ReporteResumen,
  VentaHistorial,
} from '../modelos/operaciones';

@Injectable({ providedIn: 'root' })
export class ReportesService {
  private readonly supabase = inject(SupabaseService);
  private readonly client: SupabaseClient | null = this.supabase.client;

  get conectado(): boolean {
    return this.client !== null;
  }

  async resumen(desde: string, hasta: string): Promise<ReporteResumen | null> {
    if (!this.client) return null;
    const { data, error } = await this.client.rpc('reporte_resumen', {
      p_desde: desde,
      p_hasta: hasta,
    });
    if (error || !data) return null;
    const r = data as ReporteResumen;
    return this.conNumeros(r, [
      'ventas',
      'facturado',
      'a_credito',
      'anulado',
      'efectivo',
      'tarjeta',
      'transferencia',
      'abonos',
    ]) as ReporteResumen;
  }

  async ventasPorDia(desde: string, hasta: string): Promise<FilaDia[]> {
    return (await this.lista('reporte_por_dia', desde, hasta)).map(
      (f) => this.conNumeros<FilaDia>(f, ['ventas', 'facturado', 'a_credito', 'anulado', 'efectivo', 'digital']),
    );
  }

  async ventasPorCarnicero(desde: string, hasta: string): Promise<FilaCarnicero[]> {
    return (
      await this.lista('reporte_por_carnicero', desde, hasta)
    ).map((f) => this.conNumeros<FilaCarnicero>(f, ['ventas', 'cobrado', 'a_credito', 'facturado']));
  }

  async metodos(desde: string, hasta: string): Promise<FilaMetodo[]> {
    return (await this.lista('reporte_metodos', desde, hasta)).map((f) =>
      this.conNumeros<FilaMetodo>(f, ['monto']),
    );
  }

  async topProductos(desde: string, hasta: string): Promise<FilaTopProducto[]> {
    return (await this.lista('reporte_top_productos', desde, hasta)).map((f) =>
      this.conNumeros<FilaTopProducto>(f, ['cantidad', 'total']),
    );
  }

  async ventas(desde: string, hasta: string): Promise<VentaHistorial[]> {
    if (!this.client) return [];
    const { data, error } = await this.client.rpc('reporte_ventas', {
      p_desde: desde,
      p_hasta: hasta,
    });
    if (error || !data) return [];
    return ((data as VentaHistorial[] | null) ?? []).map((v) => ({
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

  private async lista(rpc: string, desde: string, hasta: string): Promise<unknown[]> {
    if (!this.client) return [];
    const { data, error } = await this.client.rpc(rpc, {
      p_desde: desde,
      p_hasta: hasta,
    });
    if (error || !data) return [];
    return data as unknown[];
  }

  private conNumeros<T extends object>(obj: unknown, campos: string[]): T {
    const fuente = (obj ?? {}) as Record<string, unknown>;
    const salida: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(fuente)) {
      salida[k] = campos.includes(k) ? Number(v) : v;
    }
    return salida as T;
  }
}