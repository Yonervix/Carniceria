import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe, DatePipe } from '@angular/common';
import { CajaService } from '../../core/services/caja.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';

@Component({
  selector: 'app-caja',
  imports: [DecimalPipe, DatePipe, NavComponent],
  templateUrl: './caja.component.html',
})
export class CajaComponent {
  private readonly cajaService = inject(CajaService);
  private readonly aviso = inject(AvisoService);

  protected readonly estado = this.cajaService.estado;
  protected readonly ventasHoy = this.cajaService.ventasHoy;
  protected readonly cargando = this.cajaService.cargando;
  protected readonly sinBackend = this.cajaService.sinBackend;

  protected readonly efectivoInicial = signal('0');
  protected readonly efectivoCierre = signal('');

  protected readonly esperado = computed(() => {
    const e = this.estado();
    return e ? e.efectivo_inicial + e.ventas_total : 0;
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
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo cerrar la caja', 'err');
    }
  }
}