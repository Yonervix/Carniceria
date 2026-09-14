import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { CatalogoService } from '../../core/services/catalogo.service';
import { CajaService } from '../../core/services/caja.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';
import { PesajeComponent } from './pesaje.component';
import {
  redondear,
  redondearPeso,
  type ProductoCatalogo,
  type TicketItem,
} from '../../core/modelos/catalogo';

@Component({
  selector: 'app-pos',
  imports: [DecimalPipe, RouterLink, NavComponent, PesajeComponent],
  templateUrl: './pos.component.html',
})
export class PosComponent {
  private readonly catalogo = inject(CatalogoService);
  private readonly cajaService = inject(CajaService);
  private readonly aviso = inject(AvisoService);

  protected readonly productos = this.catalogo.productos;
  protected readonly cargando = this.catalogo.cargando;
  protected readonly sinBackend = this.catalogo.sinBackend;
  protected readonly error = this.catalogo.error;

  protected readonly estadoCaja = this.cajaService.estado;
  protected readonly cajaConectada = this.cajaService.conectado;
  protected readonly cajaAbierta = computed(() => this.estadoCaja()?.abierta === true);

  protected readonly categorias = [
    { slug: 'res', nombre: 'Res' },
    { slug: 'cerdo', nombre: 'Cerdo' },
    { slug: 'pollo', nombre: 'Pollo' },
    { slug: 'elaborados', nombre: 'Elaborados' },
  ];

  protected readonly categoriaActiva = signal<string | null>(null);
  protected readonly ticket = signal<TicketItem[]>([]);
  protected readonly productoPesando = signal<ProductoCatalogo | null>(null);

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

  teclaCategoria(slug: string | null): void {
    this.categoriaActiva.set(slug);
  }

  tocarProducto(p: ProductoCatalogo): void {
    if (p.cantidad <= 0) {
      this.aviso.mostrar('Sin existencia', 'err');
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
    const cantidadExacta = p.modo_venta === 'weight' ? redondearPeso(cantidad) : redondear(cantidad);
    if (cantidadExacta <= 0) return;
    const subtotal = redondear(p.precio * cantidadExacta);
    this.ticket.update((t) => {
      const idx = t.findIndex((i) => i.productoId === p.id);
      const nueva: TicketItem = {
        productoId: p.id,
        nombre: p.nombre,
        modo_venta: p.modo_venta,
        medida: p.medida,
        precio: p.precio,
        cantidad: cantidadExacta,
        subtotal,
      };
      if (idx < 0) return [...t, nueva];
      return t.map((item, i) =>
        i === idx
          ? {
              ...item,
              cantidad:
                p.modo_venta === 'weight'
                  ? redondearPeso(item.cantidad + cantidadExacta)
                  : redondear(item.cantidad + cantidadExacta),
              subtotal: redondear(item.subtotal + subtotal),
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

  async cobrar(): Promise<void> {
    const items = this.ticket().map((i) => ({ producto_id: i.productoId, cantidad: i.cantidad }));
    if (items.length === 0) return;
    const res = await this.cajaService.registrarVenta(items);
    if (res.ok) {
      this.ticket.set([]);
      this.aviso.mostrar('Venta registrada · despacho y caja al día', 'ok');
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo registrar la venta', 'err');
    }
  }
}