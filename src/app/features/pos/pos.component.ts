import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { CatalogoService } from '../../core/services/catalogo.service';
import { PesajeComponent } from './pesaje.component';
import { redondear, type ProductoCatalogo, type TicketItem } from '../../core/modelos/catalogo';

type TipoAviso = 'ok' | 'info' | 'err';

@Component({
  selector: 'app-pos',
  imports: [DecimalPipe, PesajeComponent],
  templateUrl: './pos.component.html',
})
export class PosComponent {
  private readonly catalogo = inject(CatalogoService);

  protected readonly productos = this.catalogo.productos;
  protected readonly cargando = this.catalogo.cargando;
  protected readonly sinBackend = this.catalogo.sinBackend;
  protected readonly error = this.catalogo.error;

  protected readonly categorias = [
    { slug: 'res', nombre: 'Res' },
    { slug: 'cerdo', nombre: 'Cerdo' },
    { slug: 'pollo', nombre: 'Pollo' },
    { slug: 'elaborados', nombre: 'Elaborados' },
  ];

  protected readonly categoriaActiva = signal<string | null>(null);
  protected readonly ticket = signal<TicketItem[]>([]);
  protected readonly productoPesando = signal<ProductoCatalogo | null>(null);
  protected readonly aviso = signal<{ texto: string; tipo: TipoAviso } | null>(null);
  protected readonly oscuro = signal(false);

  protected readonly filtrados = computed(() => {
    const activa = this.categoriaActiva();
    const lista = this.productos();
    return activa ? lista.filter((p) => p.categoria === activa) : lista;
  });

  protected readonly conteoArticulos = computed(() =>
    this.ticket().reduce((acc, i) => acc + i.cantidad, 0),
  );

  protected readonly total = computed(() =>
    this.ticket().reduce((acc, i) => acc + i.subtotal, 0),
  );

  private temporizadorAviso: ReturnType<typeof setTimeout> | undefined;

  protected avisoClases(a: { texto: string; tipo: TipoAviso }): string {
    const fondo =
      a.tipo === 'ok' ? 'bg-oliva-700' : a.tipo === 'err' ? 'bg-buey-900' : 'bg-piedra-950';
    return `fixed left-1/2 top-5 z-[70] -translate-x-1/2 animate-panel-in rounded-control px-4 py-2.5 text-sm font-medium shadow-premium text-piedra-50 ${fondo}`;
  }

  constructor() {
    const guardado =
      typeof localStorage !== 'undefined' && localStorage.getItem('corte-tema') === 'oscuro';
    this.oscuro.set(guardado);
    document.documentElement.classList.toggle('dark', guardado);
    this.catalogo.suscribir();
  }

  teclaCategoria(slug: string | null): void {
    this.categoriaActiva.set(slug);
  }

  tocarProducto(p: ProductoCatalogo): void {
    if (p.cantidad <= 0) {
      this.avisar('Sin existencia', 'err');
      return;
    }
    if (p.modo_venta === 'weight') {
      this.productoPesando.set(p);
      return;
    }
    this.agregarAlTicket(p, 1);
  }

  agregarAlTicket(p: ProductoCatalogo, cantidad: number): void {
    if (cantidad <= 0) return;
    this.ticket.update((t) => {
      const idx = t.findIndex((i) => i.productoId === p.id);
      const nueva: TicketItem = {
        productoId: p.id,
        nombre: p.nombre,
        modo_venta: p.modo_venta,
        medida: p.medida,
        precio: p.precio,
        cantidad: redondear(cantidad),
        subtotal: redondear(p.precio * cantidad),
      };
      if (idx < 0) return [...t, nueva];
      return t.map((item, i) =>
        i === idx
          ? {
              ...item,
              cantidad: redondear(item.cantidad + cantidad),
              subtotal: redondear(item.subtotal + nueva.subtotal),
            }
          : item,
      );
    });
  }

  confirmarPeso(peso: number): void {
    const p = this.productoPesando();
    if (!p || peso <= 0) return;
    this.agregarAlTicket(p, peso);
    this.productoPesando.set(null);
  }

  cerrarPesaje(): void {
    this.productoPesando.set(null);
  }

  quitar(index: number): void {
    this.ticket.update((t) => t.filter((_, i) => i !== index));
  }

  vaciar(): void {
    this.ticket.set([]);
  }

  cobrar(): void {
    if (this.ticket().length === 0) return;
    this.avisar('Cobro listo · el registro de la venta llega en el Bloque 3', 'ok');
  }

  alternarOscuro(): void {
    const proximo = !this.oscuro();
    this.oscuro.set(proximo);
    document.documentElement.classList.toggle('dark', proximo);
    localStorage.setItem('corte-tema', proximo ? 'oscuro' : 'claro');
  }

  private avisar(texto: string, tipo: TipoAviso): void {
    this.aviso.set({ texto, tipo });
    clearTimeout(this.temporizadorAviso);
    this.temporizadorAviso = setTimeout(() => this.aviso.set(null), 3200);
  }
}