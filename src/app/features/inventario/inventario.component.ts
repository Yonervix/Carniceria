import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { CatalogoService } from '../../core/services/catalogo.service';
import { AuthService } from '../../core/services/auth.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';
import type { ProductoCatalogo } from '../../core/modelos/catalogo';

type FiltroStock = 'todos' | 'minimo' | 'agotados';

interface FormularioAlta {
  nombre: string;
  descripcion: string;
  categoriaSlug: string;
  modoVenta: 'weight' | 'unit';
  medida: string;
  precio: string;
  precioCompra: string;
  cantidadInicial: string;
  imagenUrl: string;
}

interface FormularioEditar {
  nombre: string;
  descripcion: string;
  categoriaSlug: string;
  modoVenta: 'weight' | 'unit';
  medida: string;
  precio: string;
  precioCompra: string;
  imagenUrl: string;
  stockMinimo: string;
  stockActual: string;
  ubicacion: string;
  activo: boolean;
}

function formularioVacio(): FormularioAlta {
  return {
    nombre: '',
    descripcion: '',
    categoriaSlug: '',
    modoVenta: 'unit',
    medida: 'kg',
    precio: '',
    precioCompra: '',
    cantidadInicial: '',
    imagenUrl: '',
  };
}

function numero(valor: string): number {
  const n = parseFloat(valor.replace(',', '.'));
  return Number.isFinite(n) ? n : 0;
}

@Component({
  selector: 'app-inventario',
  imports: [DecimalPipe, RouterLink, NavComponent],
  templateUrl: './inventario.component.html',
})
export class InventarioComponent {
  private readonly catalogo = inject(CatalogoService);
  private readonly auth = inject(AuthService);
  private readonly aviso = inject(AvisoService);

  protected readonly productos = this.catalogo.productos;
  protected readonly categorias = this.catalogo.categorias;
  protected readonly cargando = this.catalogo.cargando;
  protected readonly sinBackend = this.catalogo.sinBackend;
  protected readonly error = this.catalogo.error;
  protected readonly sesion = this.auth.sesion;

  protected readonly esJefe = computed(() => this.auth.sesion()?.rol === 'jefe');

  protected readonly filtro = signal<FiltroStock>('todos');
  protected readonly busqueda = signal('');
  protected readonly modalAbierto = signal(false);
  protected readonly formulario = signal<FormularioAlta>(formularioVacio());
  protected readonly enviando = signal(false);
  protected readonly errores = signal('');

  protected readonly nuevaCategoria = signal('');
  protected readonly creandoCategoria = signal(false);

  protected readonly editando = signal<ProductoCatalogo | null>(null);
  protected readonly formEditar = signal<FormularioEditar | null>(null);
  protected readonly guardandoEdicion = signal(false);
  protected readonly errorEdicion = signal('');

  protected readonly categoriaValida = computed(() => {
    const nombre = this.nuevaCategoria().trim();
    return nombre.length >= 2 && nombre.length <= 30;
  });

  protected readonly imagenValida = computed(() => {
    const url = this.formulario().imagenUrl.trim();
    return url === '' || /^https?:\/\/\S+$/i.test(url);
  });

  protected imagenOk(url: string): boolean {
    return /^https?:\/\/\S+$/i.test(url.trim());
  }

  protected readonly enMinimo = computed(
    () => this.productos().filter((p) => p.en_minimo && p.cantidad > 0).length,
  );
  protected readonly agotados = computed(
    () => this.productos().filter((p) => p.cantidad <= 0).length,
  );
  protected readonly valorVitrina = computed(() =>
    this.productos().reduce((acc, p) => acc + (p.cantidad <= 0 ? 0 : p.cantidad * p.precio), 0),
  );

  protected readonly filtrados = computed(() => {
    const q = this.busqueda().trim().toLowerCase();
    const lista = this.productos().filter((p) => {
      if (this.filtro() === 'minimo' && !(p.en_minimo && p.cantidad > 0)) return false;
      if (this.filtro() === 'agotados' && p.cantidad > 0) return false;
      return true;
    });
    if (!q) return lista;
    return lista.filter(
      (p) =>
        p.nombre.toLowerCase().includes(q) || (p.descripcion?.toLowerCase() ?? '').includes(q),
    );
  });

  protected readonly filtros: FiltroStock[] = ['todos', 'minimo', 'agotados'];

  protected etiquetaFiltro(f: FiltroStock): string {
    return f === 'todos' ? 'Todo' : f === 'minimo' ? 'En mínimo' : 'Agotados';
  }

  protected teclaFiltro(f: FiltroStock): void {
    this.filtro.set(f);
  }

  protected buscar(valor: string): void {
    this.busqueda.set(valor);
  }

  protected abrirModal(): void {
    this.formulario.set(formularioVacio());
    this.errores.set('');
    this.modalAbierto.set(true);
  }

  protected cerrarModal(): void {
    if (this.enviando()) return;
    this.modalAbierto.set(false);
  }

  protected campo(campo: keyof FormularioAlta, valor: string): void {
    this.formulario.update((f) => (campo === 'modoVenta' ? f : { ...f, [campo]: valor }));
  }

  protected cambiarModoVenta(valor: string): void {
    this.formulario.update((f) => ({
      ...f,
      modoVenta: valor === 'weight' ? 'weight' : 'unit',
      medida: valor === 'weight' ? f.medida || 'kg' : 'kg',
    }));
  }

  protected async guardarCategoria(): Promise<void> {
    if (!this.categoriaValida()) return;
    this.creandoCategoria.set(true);
    const res = await this.catalogo.crearCategoria(this.nuevaCategoria());
    this.creandoCategoria.set(false);
    if (!res.ok) {
      this.errores.set(res.error ?? 'No se pudo crear la categoría.');
      return;
    }
    const slug = res.slug;
    if (slug) {
      this.formulario.update((f) => ({ ...f, categoriaSlug: slug }));
    }
    this.nuevaCategoria.set('');
    this.errores.set('');
  }

  protected async abrirEdicion(p: ProductoCatalogo): Promise<void> {
    if (!this.esJefe()) return;
    const costo = await this.catalogo.costoDe(p.id);
    this.editando.set(p);
    this.formEditar.set({
      nombre: p.nombre,
      descripcion: p.descripcion ?? '',
      categoriaSlug: p.categoria,
      modoVenta: p.modo_venta,
      medida: p.medida ?? 'kg',
      precio: String(p.precio),
      precioCompra: costo > 0 ? String(costo) : '',
      imagenUrl: p.imagen_url ?? '',
      stockMinimo: String(p.minimo),
      stockActual: String(p.cantidad),
      ubicacion: p.ubicacion ?? '',
      activo: true,
    });
    this.errorEdicion.set('');
  }

  protected cerrarEdicion(): void {
    if (this.guardandoEdicion()) return;
    this.editando.set(null);
    this.formEditar.set(null);
    this.errorEdicion.set('');
  }

  protected campoEditar(campo: 'nombre' | 'descripcion' | 'categoriaSlug' | 'medida' | 'precio' | 'precioCompra' | 'imagenUrl' | 'stockMinimo' | 'stockActual' | 'ubicacion', valor: string): void {
    this.formEditar.update((f) => (f ? { ...f, [campo]: valor } : f));
  }

  protected cambiarModoVentaEditar(valor: string): void {
    this.formEditar.update((f) =>
      f
        ? {
            ...f,
            modoVenta: valor === 'weight' ? 'weight' : 'unit',
            medida: valor === 'weight' ? f.medida || 'kg' : 'kg',
          }
        : f,
    );
  }

  protected alternarActivo(): void {
    this.formEditar.update((f) => (f ? { ...f, activo: !f.activo } : f));
  }

  protected async guardarEdicion(): Promise<void> {
    const p = this.editando();
    const f = this.formEditar();
    if (!p || !f) return;
    if (!f.nombre.trim()) {
      this.errorEdicion.set('El nombre es obligatorio.');
      return;
    }
    if (f.imagenUrl.trim() && !/^https?:\/\/\S+$/i.test(f.imagenUrl.trim())) {
      this.errorEdicion.set('La foto debe ser una dirección http(s) válida.');
      return;
    }

    this.guardandoEdicion.set(true);
    this.errorEdicion.set('');
    const res = await this.catalogo.actualizarProducto({
      id: p.id,
      nombre: f.nombre,
      descripcion: f.descripcion,
      categoriaSlug: f.categoriaSlug,
      modoVenta: f.modoVenta,
      medida: f.modoVenta === 'weight' ? f.medida : '',
      precio: numero(f.precio),
      precioCompra: numero(f.precioCompra) > 0 ? numero(f.precioCompra) : null,
      imagenUrl: f.imagenUrl,
      stockMinimo: numero(f.stockMinimo),
      stockActual: f.stockActual.trim() === '' ? null : numero(f.stockActual),
      ubicacion: f.ubicacion,
      activo: f.activo,
    });
    this.guardandoEdicion.set(false);

    if (!res.ok) {
      this.errorEdicion.set(res.error ?? 'No se pudo guardar.');
      return;
    }
    this.aviso.mostrar(`${f.nombre.trim()} actualizado`, 'ok');
    this.cerrarEdicion();
  }

  protected async guardarAlta(): Promise<void> {
    const f = this.formulario();
    if (!f.nombre.trim()) {
      this.errores.set('El nombre es obligatorio.');
      return;
    }
    if (!this.imagenValida()) {
      this.errores.set('La foto debe ser una dirección http(s) válida.');
      return;
    }
    const cantidad = numero(f.cantidadInicial);
    const precio = numero(f.precio);

    this.enviando.set(true);
    this.errores.set('');
    const res = await this.catalogo.altaProducto({
      nombre: f.nombre,
      descripcion: f.descripcion,
      categoriaSlug: f.categoriaSlug,
      modoVenta: f.modoVenta,
      medida: f.modoVenta === 'weight' ? f.medida : '',
      precio,
      precioCompra: numero(f.precioCompra),
      cantidadInicial: cantidad,
      imagenUrl: f.imagenUrl,
    });
    this.enviando.set(false);

    if (!res.ok) {
      this.errores.set(res.error ?? 'No se pudo guardar.');
      return;
    }
    this.aviso.mostrar(
      `${f.nombre.trim()} en vitrina${cantidad > 0 ? ` · ${cantidad}` : ''}`,
      'ok',
    );
    this.modalAbierto.set(false);
  }
}