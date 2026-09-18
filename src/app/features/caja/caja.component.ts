import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe, DatePipe } from '@angular/common';
import { CajaService } from '../../core/services/caja.service';
import { AuthService } from '../../core/services/auth.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';
import { ReciboComponent } from '../recibo/recibo.component';
import type { PagoVenta, TurnoCajaHistorial, VentaHistorial } from '../../core/modelos/operaciones';

@Component({
  selector: 'app-caja',
  imports: [DecimalPipe, DatePipe, NavComponent, ReciboComponent],
  templateUrl: './caja.component.html',
})
export class CajaComponent {
  private readonly cajaService = inject(CajaService);
  private readonly auth = inject(AuthService);
  private readonly aviso = inject(AvisoService);

  protected readonly estado = this.cajaService.estado;
  protected readonly ventasHoy = this.cajaService.ventasHoy;
  protected readonly historial = this.cajaService.historial;
  protected readonly cargando = this.cajaService.cargando;
  protected readonly sinBackend = this.cajaService.sinBackend;

  protected readonly esJefe = computed(() => this.auth.sesion()?.rol === 'jefe');
  protected readonly anulandoId = signal<string | null>(null);
  protected readonly cajaAbierta = computed(() => this.estado()?.abierta === true);

  protected readonly detalleTurno = signal<TurnoCajaHistorial | null>(null);
  protected readonly ventasDetalle = signal<VentaHistorial[]>([]);
  protected readonly cargandoDetalle = signal(false);
  protected readonly reciboVenta = signal<VentaHistorial | null>(null);

  protected readonly reabriendo = signal(false);

  protected readonly efectivoInicial = signal('0');
  protected readonly efectivoCierre = signal('');

  protected readonly esperado = computed(() => {
    const e = this.estado();
    return e ? e.efectivo_inicial + (e.efectivo_cobrado ?? 0) : 0;
  });

  protected readonly digital = computed(() => {
    const e = this.estado();
    return e ? e.digital_cobrado ?? 0 : 0;
  });

  protected readonly diferencia = computed(() => {
    const n = parseFloat(this.efectivoCierre());
    if (Number.isNaN(n)) return 0;
    return n - this.esperado();
  });

  protected readonly cierreValido = computed(() => {
    const n = parseFloat(this.efectivoCierre());
    return !Number.isNaN(n) && n >= 0;
  });

  protected readonly diferenciaFinal = computed(() => {
    const e = this.estado();
    if (!e || e.efectivo_final === null) return 0;
    return e.efectivo_final - this.esperado();
  });

  constructor() {
    void this.cajaService.cargarHistorial();
  }

  protected resumenArticulos(v: VentaHistorial): string {
    const lista = v.articulos ?? [];
    if (lista.length === 0) return v.carnicero || 'Carnicero';
    return lista.map((a) => `${a.nombre} ×${a.cantidad}`).join(' · ');
  }

  protected etiquetaPagos(v: VentaHistorial): string {
    const pagos = v.pagos ?? [];
    if (v.cliente_id) return `A crédito · ${v.cliente ?? 'cliente'}`;
    if (pagos.length === 0) return 'Efectivo';
    const partes = pagos.map((p) => `${this.nombreMetodo(p.metodo)} $${p.monto.toFixed(2)}`);
    return partes.join(' + ');
  }

  protected nombreMetodo(m: string): string {
    if (m === 'tarjeta') return 'Tarjeta';
    if (m === 'transferencia') return 'Transferencia';
    return 'Efectivo';
  }

  protected montoMetodo(pagos: PagoVenta[], metodo: string): number {
    const p = pagos.find((x) => x.metodo === metodo);
    return p ? p.monto : 0;
  }

  protected readonly detalleEsperado = computed(() => {
    const t = this.detalleTurno();
    return t ? t.efectivo_inicial + (t.efectivo_cobrado ?? 0) : 0;
  });

  protected readonly detalleDigital = computed(() => {
    const t = this.detalleTurno();
    return t ? t.digital_cobrado ?? 0 : 0;
  });

  protected readonly detalleDiferencia = computed(() => {
    const t = this.detalleTurno();
    if (!t || t.efectivo_final === null) return 0;
    return t.efectivo_final - this.detalleEsperado();
  });

  protected async abrir(): Promise<void> {
    const n = parseFloat(this.efectivoInicial());
    const res = await this.cajaService.abrir(Number.isNaN(n) ? 0 : n);
    if (res.ok) {
      this.aviso.mostrar('Caja abierta del día', 'ok');
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo abrir la caja', 'err');
    }
  }

  protected async cerrar(): Promise<void> {
    if (!this.cierreValido()) return;
    const res = await this.cajaService.cerrar(parseFloat(this.efectivoCierre()));
    if (res.ok) {
      this.aviso.mostrar('Caja cerrada · turno guardado', 'ok');
      this.efectivoCierre.set('');
      void this.cajaService.cargarHistorial();
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo cerrar la caja', 'err');
    }
  }

  protected async reabrir(): Promise<void> {
    this.reabriendo.set(true);
    const res = await this.cajaService.abrir(0);
    this.reabriendo.set(false);
    if (res.ok) {
      this.aviso.mostrar('Caja reabierta del día', 'ok');
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo reabrir la caja', 'err');
    }
  }

  protected async verTurno(t: TurnoCajaHistorial): Promise<void> {
    this.detalleTurno.set(t);
    this.ventasDetalle.set([]);
    this.cargandoDetalle.set(true);
    this.ventasDetalle.set(await this.cajaService.ventasDeCaja(t.id));
    this.cargandoDetalle.set(false);
  }

  protected cerrarDetalle(): void {
    this.detalleTurno.set(null);
    this.ventasDetalle.set([]);
  }

  protected async anular(v: VentaHistorial): Promise<void> {
    if (this.anulandoId() !== v.id) {
      this.anulandoId.set(v.id);
      return;
    }
    this.anulandoId.set(null);
    const res = await this.cajaService.anularVenta(v.id);
    if (res.ok) {
      this.aviso.mostrar('Venta anulada · stock restaurado', 'ok');
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo anular la venta', 'err');
    }
  }
}