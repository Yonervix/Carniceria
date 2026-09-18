import { Component, input, output } from '@angular/core';
import { DecimalPipe, DatePipe } from '@angular/common';
import { NEGOCIO } from '../../core/utilidades/negocio';
import type { ItemVentaHistorial, VentaHistorial } from '../../core/modelos/operaciones';

@Component({
  selector: 'app-recibo',
  imports: [DecimalPipe, DatePipe],
  templateUrl: './recibo.component.html',
})
export class ReciboComponent {
  readonly venta = input<VentaHistorial | null>(null);
  readonly cerrarAccion = output<void>();

  protected readonly negocio = NEGOCIO;

  protected folio(v: VentaHistorial): string {
    return `R-${(v.id || '').replace(/-/g, '').slice(0, 6).toUpperCase()}`;
  }

  protected cantidadLinea(a: ItemVentaHistorial): string {
    const medida = a.medida ?? '';
    if (medida && medida !== 'u') {
      const kg = a.cantidad
        .toFixed(3)
        .replace(/0+$/, '')
        .replace(/\.$/, '');
      return `${kg} ${medida}`;
    }
    return `${a.cantidad.toLocaleString('es-MX', { maximumFractionDigits: 0 })} u`;
  }

  protected nombreMetodo(m: string): string {
    if (m === 'tarjeta') return 'Tarjeta';
    if (m === 'transferencia') return 'Transferencia';
    return 'Efectivo';
  }

  protected efectivoNeto(v: VentaHistorial): number {
    return (v.pagos ?? []).reduce((acc, p) => (p.metodo === 'efectivo' ? acc + p.monto : acc), 0);
  }

  protected imprimir(): void {
    window.print();
  }
}