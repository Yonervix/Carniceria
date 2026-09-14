import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { CatalogoService } from '../../core/services/catalogo.service';
import { StockService } from '../../core/services/stock.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';

interface FilaDestino {
  id: string;
  peso: string;
}

@Component({
  selector: 'app-mermas',
  imports: [DecimalPipe, NavComponent],
  templateUrl: './mermas.component.html',
})
export class MermasComponent {
  private readonly catalogo = inject(CatalogoService);
  private readonly stock = inject(StockService);
  private readonly aviso = inject(AvisoService);

  protected readonly productos = this.catalogo.productos;
  protected readonly sinBackend = this.catalogo.sinBackend;
  protected readonly movimientos = this.stock.movimientos;
  protected readonly cargandoMov = this.stock.cargandoMovimientos;

  protected readonly pesos = computed(() =>
    this.productos().filter((p) => p.modo_venta === 'weight'),
  );

  protected readonly mermaProductoId = signal('');
  protected readonly mermaCantidad = signal('');
  protected readonly mermaNota = signal('');

  protected readonly mermaValida = computed(() => {
    const id = this.mermaProductoId();
    const n = parseFloat(this.mermaCantidad());
    return !!id && n > 0 && n <= (this.productos().find((p) => p.id === id)?.cantidad ?? n);
  });

  protected readonly origenId = signal('');
  protected readonly pesoOrigen = signal('');
  protected readonly destinos = signal<FilaDestino[]>([]);
  protected readonly desposteNota = signal('');

  protected readonly pesoOrigenNum = computed(() => parseFloat(this.pesoOrigen()) || 0);

  protected readonly sumaDestinos = computed(() =>
    this.destinos().reduce((acc, d) => acc + (parseFloat(d.peso) || 0), 0),
  );

  protected readonly desposteValido = computed(() => {
    const o = this.origenId();
    const peso = this.pesoOrigenNum();
    const filas = this.destinos().filter((d) => d.id && parseFloat(d.peso) > 0);
    return !!o && peso > 0 && filas.length > 0 && this.sumaDestinos() > 0 && this.sumaDestinos() <= peso;
  });

  constructor() {
    void this.stock.cargarMovimientos();
  }

  protected elegirProductoMerma(valor: string): void {
    this.mermaProductoId.set(valor);
  }

  protected async guardarMerma(): Promise<void> {
    if (!this.mermaValida()) {
      this.aviso.mostrar('Elige un corte y una cantidad válida', 'info');
      return;
    }
    const res = await this.stock.merma(
      this.mermaProductoId(),
      parseFloat(this.mermaCantidad()),
      this.mermaNota().trim() || null,
    );
    if (res.ok) {
      this.aviso.mostrar('Merma registrada', 'ok');
      this.mermaCantidad.set('');
      this.mermaNota.set('');
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo registrar', 'err');
    }
  }

  protected elegirOrigen(valor: string): void {
    this.origenId.set(valor);
  }

  protected agregarDestino(): void {
    this.destinos.update((d) => [...d, { id: '', peso: '' }]);
  }

  protected quitarDestino(i: number): void {
    this.destinos.update((d) => d.filter((_, x) => x !== i));
  }

  protected cambiarDestino(i: number, id: string): void {
    this.destinos.update((d) => d.map((fila, x) => (x === i ? { ...fila, id } : fila)));
  }

  protected cambiarPesoDestino(i: number, peso: string): void {
    this.destinos.update((d) => d.map((fila, x) => (x === i ? { ...fila, peso } : fila)));
  }

  protected usadaEnOtroDestino(id: string, filaActual: string): boolean {
    return id !== filaActual && this.destinos().some((d) => d.id === id);
  }

  protected async procesarDesposte(): Promise<void> {
    if (!this.desposteValido()) {
      this.aviso.mostrar('Revisa el origen, el peso y los destinos', 'info');
      return;
    }
    const destinos = this.destinos()
      .filter((d) => d.id && parseFloat(d.peso) > 0)
      .map((d) => ({ producto_id: d.id, peso: parseFloat(d.peso) }));
    const res = await this.stock.desposte(
      this.origenId(),
      this.pesoOrigenNum(),
      destinos,
      this.desposteNota().trim() || null,
    );
    if (res.ok) {
      this.aviso.mostrar('Desposte procesado · pieza descontada', 'ok');
      this.pesoOrigen.set('');
      this.destinos.set([]);
      this.desposteNota.set('');
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo procesar', 'err');
    }
  }

  protected etiquetaConcepto(c: string): string {
    const mapa: Record<string, string> = {
      inicial: 'Inicial',
      compra: 'Compra',
      venta: 'Venta',
      merma: 'Merma',
      desposte: 'Desposte',
      ajuste: 'Ajuste',
    };
    return mapa[c] ?? c;
  }

  protected claseConcepto(c: string): string {
    const base = 'rounded-full px-2.5 py-1 text-[11px] font-medium';
    if (c === 'venta') return `${base} bg-oliva-100 text-oliva-800`;
    if (c === 'merma') return `${base} bg-buey-100 text-buey-800`;
    if (c === 'desposte') return `${base} bg-piedra-200/70 text-piedra-600`;
    return `${base} bg-piedra-200/70 text-piedra-600`;
  }
}