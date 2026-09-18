import { Injectable, signal } from '@angular/core';
import type { Aviso, TipoAviso } from '../modelos/operaciones';

@Injectable({ providedIn: 'root' })
export class AvisoService {
  private temporizador: ReturnType<typeof setTimeout> | undefined;

  readonly aviso = signal<Aviso | null>(null);

  mostrar(texto: string, tipo: TipoAviso, duracion = 3200): void {
    this.aviso.set({ texto, tipo });
    clearTimeout(this.temporizador);
    this.temporizador = setTimeout(() => this.aviso.set(null), duracion);
  }
}