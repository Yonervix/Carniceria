import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { CatalogoService } from '../../core/services/catalogo.service';
import { CajaService } from '../../core/services/caja.service';
import { AvisoService } from '../../core/services/aviso.service';
import { AuthService } from '../../core/services/auth.service';
import { NavComponent } from '../../core/navegacion/nav.component';
import { PesajeComponent } from './pesaje.component';
import { ReciboComponent } from '../recibo/recibo.component';
import {
  redondear,
  redondearPeso,
  type ProductoCatalogo,
  type TicketItem,
} from '../../core/modelos/catalogo';
import type { Cliente, MetodoPago, PagoVenta, VentaHistorial } from '../../core/modelos/operaciones';

interface FilaPago {
  metodo: MetodoPago;
  texto: string;
  monto: number;
}

function parseMonto(valor: string): number {
  const n = parseFloat(String(valor).replace(',', '.'));
  return Number.isFinite(n) && n > 0 ? redondear(n) : 0;
}

const NOMBRE_METODO: Record<MetodoPago, string> = {
  efectivo: 'Efectivo',
  tarjeta: 'Tarjeta',
  transferencia: 'Transferencia',
};

@Component({
  selector: 'app-pos',
  imports: [DecimalPipe, RouterLink, NavComponent, PesajeComponent, ReciboComponent],
  templateUrl: './pos.component.html',
})
export class PosComponent {
  private readonly catalogo = inject(CatalogoService);
  private readonly cajaService = inject(CajaService);
  private readonly aviso = inject(AvisoService);
  private readonly auth = inject(AuthService);

  protected readonly productos = this.catalogo.productos;
  protected readonly cargando = this.catalogo.cargando;
  protected readonly sinBackend = this.catalogo.sinBackend;
  protected readonly error = this.catalogo.error;

  protected readonly redondear = redondear;

  protected readonly estadoCaja = this.cajaService.estado;
  protected readonly cajaConectada = this.cajaService.conectado;
  protected readonly cajaAbierta = computed(() => this.estadoCaja()?.abierta === true);

  protected readonly categorias = this.catalogo.categorias;

  protected readonly categoriaActiva = signal<string | null>(null);
  protected readonly ticket = signal<TicketItem[]>([]);
  protected readonly productoPesando = signal<ProductoCatalogo | null>(null);

  protected readonly cobrando = signal(false);
  protected readonly aCredito = signal(false);
  protected readonly filas = signal<FilaPago[]>([]);
  protected readonly clientes = signal<Cliente[]>([]);
  protected readonly clienteId = signal<string | null>(null);
  protected readonly nuevoCliente = signal('');
  protected readonly metodosActivos = signal<MetodoPago[]>(['efectivo']);
  protected readonly reciboVenta = signal<VentaHistorial | null>(null);

  protected readonly nombresMetodo = NOMBRE_METODO;

  protected readonly metodosPago: MetodoPago[] = ['efectivo', 'tarjeta', 'transferencia'];

  protected readonly pagado = computed(() =>
    redondear(this.filas().reduce((acc, f) => acc + (Number.isFinite(f.monto) ? f.monto : 0), 0)),
  );

  protected readonly porPagar = computed(() => redondear(this.total() - this.pagado()));

  protected readonly sobra = computed(() => this.porPagar() < 0);

  protected readonly vuelto = computed(() => (this.sobra() ? this.porPagar() * -1 : 0));

  protected readonly falta = computed(
    () => !this.aCredito() && this.porPagar() > 0.001 && !this.sobra(),
  );

  protected readonly puedeConfirmar = computed(() => {
    if (this.aCredito()) return this.clienteId() !== null;
    if (this.porPagar() > 0.001) return false;
    if (this.sobra()) {
      return this.filas().some((f) => f.metodo === 'efectivo' && f.monto > 0);
    }
    return true;
  });

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

  async abrirCobro(): Promise<void> {
    if (this.ticket().length === 0) return;
    this.aCredito.set(false);
    this.clienteId.set(null);
    this.nuevoCliente.set('');
    this.filas.set([
      { metodo: 'efectivo', texto: this.total().toFixed(2), monto: this.total() },
    ]);
    this.metodosActivos.set(['efectivo']);
    this.cobrando.set(true);
    const clientes = await this.cajaService.listarClientes();
    this.clientes.set(clientes);
  }

  cerrarCobro(): void {
    this.cobrando.set(false);
    this.aCredito.set(false);
  }

  agregarMetodo(metodo: MetodoPago): void {
    if (this.metodosActivos().includes(metodo)) return;
    this.metodosActivos.update((m) => [...m, metodo]);
    const restante = redondear(Math.max(this.porPagar(), 0));
    this.filas.update((fs) => [
      ...fs,
      { metodo, texto: restante > 0 ? restante.toFixed(2) : '', monto: restante },
    ]);
  }

  quitarMetodo(metodo: MetodoPago): void {
    if (this.metodosActivos().length === 1) return;
    this.metodosActivos.update((m) => m.filter((x) => x !== metodo));
    this.filas.update((fs) => fs.filter((f) => f.metodo !== metodo));
  }

  setMontoFila(index: number, valor: string): void {
    this.filas.update((fs) =>
      fs.map((f, i) =>
        i === index ? { ...f, texto: valor, monto: parseMonto(valor) } : f,
      ),
    );
  }

  usarEfectivoExacto(): void {
    const exacto = this.total();
    this.filas.update((fs) =>
      fs.map((f) =>
        f.metodo === 'efectivo'
          ? { ...f, texto: exacto.toFixed(2), monto: exacto }
          : f,
      ),
    );
  }

  extraEfectivo(montoExtra: number): void {
    const idx = this.filas().findIndex((f) => f.metodo === 'efectivo');
    if (idx < 0) return;
    this.filas.update((fs) =>
      fs.map((f, i) => {
        if (i !== idx) return f;
        const nuevo = redondear(f.monto + montoExtra);
        return { ...f, texto: nuevo.toFixed(2), monto: nuevo };
      }),
    );
  }

  elegirCliente(id: string): void {
    this.clienteId.set(id);
  }

  toggleCredito(): void {
    this.aCredito.set(!this.aCredito());
    if (this.aCredito() && !this.clienteId()) {
      this.clienteId.set(this.clientes()[0]?.id ?? null);
    }
  }

  async crearCliente(): Promise<void> {
    const nombre = this.nuevoCliente().trim();
    if (!nombre) {
      this.aviso.mostrar('Escribe el nombre del cliente', 'err');
      return;
    }
    const id = await this.cajaService.registrarCliente(nombre);
    if (!id) {
      this.aviso.mostrar('No se pudo crear el cliente', 'err');
      return;
    }
    this.clientes.set(await this.cajaService.listarClientes());
    this.clienteId.set(id);
    this.nuevoCliente.set('');
    this.aviso.mostrar('Cliente creado', 'ok');
  }

  private pagosLista(): PagoVenta[] {
    return this.filas()
      .filter((f) => f.monto > 0)
      .map((f) => ({ metodo: f.metodo, monto: f.monto }));
  }

  async confirmarCobro(): Promise<void> {
    if (!this.puedeConfirmar()) return;
    const items = this.ticket().map((i) => ({ producto_id: i.productoId, cantidad: i.cantidad }));
    if (items.length === 0) return;

    const credito = this.aCredito();
    let vuelto = 0;
    let pagos: PagoVenta[] = [];
    if (!credito) {
      pagos = this.pagosLista();
      const total = this.total();
      const pagado = this.pagado();
      vuelto = redondear(pagado - total);
      if (vuelto > 0) {
        const idx = pagos.findIndex((p) => p.metodo === 'efectivo');
        if (idx >= 0) {
          pagos[idx] = { ...pagos[idx], monto: redondear(pagos[idx].monto - vuelto) };
        }
      }
    }

    this.cobrando.set(false);
    this.aCredito.set(false);
    const res = await this.cajaService.registrarVenta(
      items,
      credito ? [] : pagos,
      credito ? this.clienteId() : null,
      vuelto,
    );
    if (res.ok) {
      const ticketFinal = this.ticket();
      this.reciboVenta.set(this.reciboDeVenta(res.id ?? '', ticketFinal, pagos, credito, vuelto));
      this.ticket.set([]);
      if (credito) {
        this.aviso.mostrar('Venta a crédito registrada', 'ok');
      } else if (vuelto > 0) {
        this.aviso.mostrar(`Vuelto: $ ${vuelto.toFixed(2)}`, 'ok', 6000);
      } else {
        this.aviso.mostrar('Venta registrada', 'ok');
      }
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo registrar la venta', 'err');
    }
  }

  private reciboDeVenta(
    id: string,
    ticket: TicketItem[],
    pagos: PagoVenta[],
    credito: boolean,
    vuelto: number,
  ): VentaHistorial {
    const pagoEfectivo = pagos.reduce((acc, p) => (p.metodo === 'efectivo' ? acc + p.monto : acc), 0);
    const clienteId = this.clienteId();
    const cliente = this.clientes().find((c) => c.id === clienteId)?.nombre ?? null;
    return {
      id,
      subtotal: this.total(),
      anulada: false,
      created_at: new Date().toISOString(),
      carnicero: this.auth.sesion()?.nombre ?? 'Carnicero',
      cliente_id: credito ? clienteId : null,
      cliente: credito ? cliente : null,
      articulos: ticket.map((i) => ({
        nombre: i.nombre,
        cantidad: i.cantidad,
        medida: i.medida ?? undefined,
        precio: i.precio,
        subtotal: i.subtotal,
      })),
      pagos,
      vuelto,
      efectivo_recibido: pagoEfectivo + vuelto,
    };
  }
}