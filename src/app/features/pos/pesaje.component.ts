import { Component, computed, HostListener, input, output, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { redondear, type ProductoCatalogo } from '../../core/modelos/catalogo';

@Component({
  selector: 'app-pesaje',
  imports: [DecimalPipe],
  templateUrl: './pesaje.component.html',
})
export class PesajeComponent {
  readonly producto = input.required<ProductoCatalogo>();
  readonly confirmado = output<number>();
  readonly cancelado = output<void>();

  protected readonly raw = signal('');

  protected readonly peso = computed(() =>
    this.raw() ? parseFloat(this.raw()) : 0,
  );

  protected readonly totalParcial = computed(() =>
    redondear(this.peso() * this.producto().precio),
  );

  protected readonly excede = computed(() => {
    const p = this.producto();
    const peso = this.peso();
    return p.cantidad > 0 && peso > p.cantidad;
  });

  protected readonly valido = computed(() => this.peso() > 0 && !this.excede());

  datos(): string[] {
    return ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', '·'];
  }

  digito(d: string): void {
    const actual = this.raw();
    if (d === '.') {
      if (actual === '') {
        this.raw.set('0.');
        return;
      }
      if (!actual.includes('.')) {
        this.raw.set(actual + '.');
      }
      return;
    }
    if (d === '·') {
      this.borrar();
      return;
    }
    const partes = actual.split('.');
    if (partes.length === 2 && partes[1].length >= 3) return;
    if (actual === '0' && d !== '0') {
      this.raw.set(d);
      return;
    }
    if (actual === '0') return;
    this.raw.set(actual === '' && d === '0' ? '0' : actual + d);
  }

  borrar(): void {
    this.raw.set(this.raw().slice(0, -1));
  }

  confirmar(): void {
    if (!this.valido()) return;
    this.confirmado.emit(this.peso());
  }

  @HostListener('window:keydown', ['$event'])
  protected atajo(event: KeyboardEvent): void {
    if (event.key >= '0' && event.key <= '9') {
      this.digito(event.key);
      event.preventDefault();
    } else if (event.key === '.') {
      this.digito('.');
      event.preventDefault();
    } else if (event.key === 'Backspace') {
      this.borrar();
      event.preventDefault();
    } else if (event.key === 'Enter') {
      this.confirmar();
    } else if (event.key === 'Escape') {
      this.cancelado.emit();
    }
  }
}