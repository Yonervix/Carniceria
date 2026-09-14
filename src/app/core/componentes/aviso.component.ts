import { Component, inject } from '@angular/core';
import { AvisoService } from '../../core/services/aviso.service';
import type { Aviso } from '../../core/modelos/operaciones';

@Component({
  selector: 'app-aviso',
  template: `
    @if (a.aviso(); as aviso) {
      <div [class]="clases(aviso)" role="status">{{ aviso.texto }}</div>
    }
  `,
})
export class AvisoComponent {
  protected readonly a = inject(AvisoService);

  protected clases(aviso: Aviso): string {
    const fondo =
      aviso.tipo === 'ok'
        ? 'bg-oliva-700'
        : aviso.tipo === 'err'
          ? 'bg-buey-900'
          : 'bg-piedra-950';
    return `fixed left-1/2 top-5 z-[70] -translate-x-1/2 animate-panel-in rounded-control px-4 py-2.5 text-sm font-medium shadow-premium text-piedra-50 ${fondo}`;
  }
}