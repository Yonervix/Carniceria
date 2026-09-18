import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe, DatePipe } from '@angular/common';
import { CajaService } from '../../core/services/caja.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';
import type {
  AbonoCliente,
  Cliente,
  ItemVentaHistorial,
  MetodoPago,
  VentaCliente,
} from '../../core/modelos/operaciones';

@Component({
  selector: 'app-cuentas',
  imports: [DecimalPipe, DatePipe, NavComponent],
  templateUrl: './cuentas.component.html',
})
export class CuentasComponent {
  private readonly cajaService = inject(CajaService);
  private readonly aviso = inject(AvisoService);

  protected readonly clientes = signal<Cliente[]>([]);
  protected readonly cargando = signal(true);
  protected readonly busqueda = signal('');

  protected readonly seleccion = signal<Cliente | null>(null);
  protected readonly ventasCliente = signal<VentaCliente[]>([]);
  protected readonly abonosLista = signal<AbonoCliente[]>([]);
  protected readonly ventaAbierta = signal<string | null>(null);
  protected readonly abiertoTodo = signal(false);

  protected readonly abonando = signal(false);
  protected readonly montoAbono = signal('');
  protected readonly metodoAbono = signal<MetodoPago>('efectivo');
  protected readonly nuevoCliente = signal('');
  protected readonly telefono = signal('');

  protected readonly filtrados = computed(() => {
    const q = this.busqueda().trim().toLowerCase();
    const lista = this.clientes();
    if (!q) return lista;
    return lista.filter(
      (c) => c.nombre.toLowerCase().includes(q) || (c.telefono ?? '').includes(q),
    );
  });

  protected readonly totalPorCobrar = computed(() =>
    this.clientes().reduce((acc, c) => acc + c.saldo, 0),
  );

  protected readonly totalAbonado = computed(() =>
    this.abonosLista().reduce((acc, a) => acc + a.monto, 0),
  );

  constructor() {
    void this.cargar();
  }

  private async cargar(): Promise<void> {
    this.cargando.set(true);
    this.clientes.set(await this.cajaService.listarClientes());
    this.cargando.set(false);
  }

  protected async verDetalle(c: Cliente): Promise<void> {
    this.seleccion.set(c);
    this.montoAbono.set('');
    this.metodoAbono.set('efectivo');
    this.ventaAbierta.set(null);
    this.abiertoTodo.set(false);
    this.ventasCliente.set(await this.cajaService.ventasCliente(c.id));
    this.abonosLista.set(await this.cajaService.abonosCliente(c.id));
  }

  protected cerrarDetalle(): void {
    this.seleccion.set(null);
    this.ventasCliente.set([]);
    this.abonosLista.set([]);
    this.ventaAbierta.set(null);
  }

  protected alternarVenta(id: string): void {
    this.ventaAbierta.set(this.ventaAbierta() === id ? null : id);
  }

  protected esNumeroValido(): boolean {
    const n = parseFloat(this.montoAbono().replace(',', '.'));
    return Number.isFinite(n) && n > 0;
  }

  protected async confirmarAbono(): Promise<void> {
    const c = this.seleccion();
    if (!c || !this.esNumeroValido()) return;
    const monto = parseFloat(this.montoAbono().replace(',', '.'));
    if (monto > c.saldo) {
      this.aviso.mostrar(`El abono supera la deuda ($ ${c.saldo.toFixed(2)})`, 'err');
      return;
    }
    this.abonando.set(true);
    const res = await this.cajaService.abonarCuenta(c.id, monto, this.metodoAbono());
    this.abonando.set(false);
    if (res.ok) {
      this.aviso.mostrar(`Abono registrado · queda $ ${(c.saldo - monto).toFixed(2)}`, 'ok');
      const actualizado = await this.cajaService.listarClientes();
      this.clientes.set(actualizado);
      const nuevo = actualizado.find((x) => x.id === c.id);
      if (nuevo) await this.verDetalle(nuevo);
    } else {
      this.aviso.mostrar(res.error ?? 'No se pudo registrar el abono', 'err');
    }
  }

  protected async crearCliente(): Promise<void> {
    const nombre = this.nuevoCliente().trim();
    if (!nombre) {
      this.aviso.mostrar('Escribe el nombre del cliente', 'err');
      return;
    }
    const id = await this.cajaService.registrarCliente(nombre, this.telefono());
    if (!id) {
      this.aviso.mostrar('No se pudo crear el cliente', 'err');
      return;
    }
    this.nuevoCliente.set('');
    this.telefono.set('');
    this.aviso.mostrar('Cliente creado', 'ok');
    void this.cargar();
  }

  protected etiquetaPagos(v: VentaCliente): string {
    const pagos = v.pagos ?? [];
    if (pagos.length === 0) return 'Pendiente (a crédito)';
    const partes = pagos.map((p) => `${this.nombreMetodo(p.metodo)} $${p.monto.toFixed(2)}`);
    return partes.join(' + ');
  }

  protected nombreMetodo(m: string): string {
    if (m === 'tarjeta') return 'Tarjeta';
    if (m === 'transferencia') return 'Transferencia';
    return 'Efectivo';
  }

  protected cantidadArticulo(a: ItemVentaHistorial): string {
    const medida = (a.medida ?? '').trim();
    const peso = medida && medida !== 'u';
    return peso
      ? `${a.cantidad.toFixed(3).replace(/0+$/, '').replace(/\.$/, '')} ${medida}`
      : `${a.cantidad.toLocaleString('es-MX', { maximumFractionDigits: 0 })} u`;
  }

  protected resumenCompra(v: VentaCliente): string {
    const articulos = v.articulos ?? [];
    if (articulos.length === 0) return 'Venta a crédito';
    if (articulos.length === 1) {
      return `${articulos[0].nombre} (${this.cantidadArticulo(articulos[0])})`;
    }
    const primeras = articulos.slice(0, 2).map((a) => a.nombre).join(' · ');
    const resto = articulos.length - 2;
    return resto > 0 ? `${primeras} +${resto} más` : primeras;
  }
}