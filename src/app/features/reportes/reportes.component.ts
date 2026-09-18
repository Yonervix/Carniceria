import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe, DecimalPipe } from '@angular/common';
import { ReportesService } from '../../core/services/reportes.service';
import { AuthService } from '../../core/services/auth.service';
import { NavComponent } from '../../core/navegacion/nav.component';
import type {
  FilaCarnicero,
  FilaDia,
  FilaMetodo,
  FilaTopProducto,
  ReporteResumen,
  VentaHistorial,
} from '../../core/modelos/operaciones';

type ClaveRango = 'hoy' | 'ayer' | 'semana' | 'mes' | 'personalizado';

interface OpcionRango {
  clave: ClaveRango;
  etiqueta: string;
}

function iso(d: Date): string {
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dia = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${dia}`;
}

function porClave(clave: ClaveRango): { desde: string; hasta: string } {
  const hoy = new Date();
  if (clave === 'ayer') {
    const ayer = new Date(hoy);
    ayer.setDate(hoy.getDate() - 1);
    return { desde: iso(ayer), hasta: iso(ayer) };
  }
  if (clave === 'semana') {
    const lunes = new Date(hoy);
    const dia = (hoy.getDay() + 6) % 7;
    lunes.setDate(hoy.getDate() - dia);
    return { desde: iso(lunes), hasta: iso(hoy) };
  }
  if (clave === 'mes') {
    const inicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    return { desde: iso(inicio), hasta: iso(hoy) };
  }
  return { desde: iso(hoy), hasta: iso(hoy) };
}

@Component({
  selector: 'app-reportes',
  imports: [DecimalPipe, DatePipe, NavComponent],
  templateUrl: './reportes.component.html',
})
export class ReportesComponent {
  private readonly reportes = inject(ReportesService);
  private readonly auth = inject(AuthService);
  protected readonly esJefe = computed(() => this.auth.sesion()?.rol === 'jefe');

  protected readonly opciones: OpcionRango[] = [
    { clave: 'hoy', etiqueta: 'Hoy' },
    { clave: 'ayer', etiqueta: 'Ayer' },
    { clave: 'semana', etiqueta: 'Semana' },
    { clave: 'mes', etiqueta: 'Mes' },
    { clave: 'personalizado', etiqueta: 'Personalizado' },
  ];

  protected readonly rango = signal<ClaveRango>('hoy');
  protected readonly desde = signal('');
  protected readonly hasta = signal('');
  protected readonly cargando = signal(true);

  protected readonly resumenSig = signal<ReporteResumen | null>(null);
  protected readonly porDia = signal<FilaDia[]>([]);
  protected readonly porCarnicero = signal<FilaCarnicero[]>([]);
  protected readonly metodos = signal<FilaMetodo[]>([]);
  protected readonly top = signal<FilaTopProducto[]>([]);
  protected readonly ventasLista = signal<VentaHistorial[]>([]);

  protected readonly etiquetaRango = computed(() => {
    const d = this.desde();
    const h = this.hasta();
    if (this.rango() === 'personalizado') {
      return d === h ? d : `${d} al ${h}`;
    }
    const opcion = this.opciones.find((o) => o.clave === this.rango());
    return `${opcion?.etiqueta ?? ''} · ${d === h ? d : `${d} al ${h}`}`;
  });

  protected readonly ticketPromedio = computed(() => {
    const r = this.resumenSig();
    if (!r || r.ventas === 0) return 0;
    return r.facturado / r.ventas;
  });

  protected readonly rangoValido = computed(() => {
    if (!this.desde() || !this.hasta()) return false;
    return this.desde() <= this.hasta();
  });

  constructor() {
    void this.aplicar('hoy');
  }

  protected async aplicar(clave: ClaveRango): Promise<void> {
    this.rango.set(clave);
    const { desde, hasta } = porClave(clave);
    this.desde.set(desde);
    this.hasta.set(hasta);
    await this.cargar();
  }

  protected async cambiarDesde(valor: string): Promise<void> {
    this.rango.set('personalizado');
    this.desde.set(valor);
    await this.cargar();
  }

  protected async cambiarHasta(valor: string): Promise<void> {
    this.rango.set('personalizado');
    this.hasta.set(valor);
    await this.cargar();
  }

  private async cargar(): Promise<void> {
    if (!this.rangoValido()) {
      this.cargando.set(false);
      return;
    }
    this.cargando.set(true);
    const [desde, hasta] = [this.desde(), this.hasta()];
    this.resumenSig.set(await this.reportes.resumen(desde, hasta));
    this.porDia.set(await this.reportes.ventasPorDia(desde, hasta));
    this.porCarnicero.set(await this.reportes.ventasPorCarnicero(desde, hasta));
    this.metodos.set(await this.reportes.metodos(desde, hasta));
    this.top.set(await this.reportes.topProductos(desde, hasta));
    this.ventasLista.set(await this.reportes.ventas(desde, hasta));
    this.cargando.set(false);
  }

  protected montoMetodo(metodo: string): number {
    return this.metodos().find((m) => m.metodo === metodo)?.monto ?? 0;
  }

  protected nombreMetodo(metodo: string): string {
    if (metodo === 'tarjeta') return 'Tarjeta';
    if (metodo === 'transferencia') return 'Transferencia';
    if (metodo === 'efectivo') return 'Efectivo';
    if (metodo === 'a_credito') return 'A crédito';
    return metodo;
  }

  protected cantidadTop(p: FilaTopProducto): string {
    const medida = (p.medida ?? '').trim();
    const peso = medida && medida !== 'u';
    return peso
      ? `${p.cantidad.toFixed(3).replace(/0+$/, '').replace(/\.$/, '')} ${medida}`
      : `${p.cantidad.toLocaleString('es-MX', { maximumFractionDigits: 0 })} u`;
  }

  protected porcentajeTop(p: FilaTopProducto): number {
    const max = Math.max(...this.top().map((t) => t.total), 0);
    return max > 0 ? Math.round((p.total / max) * 100) : 0;
  }

  protected diaLegible(fecha: string): string {
    const [a, m, d] = fecha.split('-').map(Number);
    const dias = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    const dt = new Date(a, m - 1, d);
    return `${dias[dt.getDay()]} ${d} ${meses[(m - 1) % 12]} ${a}`;
  }

  protected resumenVenta(v: VentaHistorial): string {
    const articulos = v.articulos ?? [];
    if (articulos.length === 0) return '—';
    if (articulos.length === 1) return articulos[0].nombre;
    return `${articulos.slice(0, 2).map((a) => a.nombre).join(' · ')}${articulos.length > 2 ? ` +${articulos.length - 2} más` : ''}`;
  }

  protected etiquetaPagos(v: VentaHistorial): string {
    const pagos = v.pagos ?? [];
    if (v.cliente_id) return 'A crédito';
    if (pagos.length === 0) return 'Efectivo';
    return pagos.map((p) => `${this.nombreMetodo(p.metodo)} $${p.monto.toFixed(2)}`).join(' + ');
  }

  protected imprimir(): void {
    window.print();
  }
}