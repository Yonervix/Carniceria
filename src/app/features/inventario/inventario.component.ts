import { Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { CatalogoService } from '../../core/services/catalogo.service';
import { AuthService } from '../../core/services/auth.service';
import { AvisoService } from '../../core/services/aviso.service';
import { NavComponent } from '../../core/navegacion/nav.component';

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
}

function formularioVacio(): FormularioAlta {
  return {
    nombre: '',
    descripcion: '',
    categoriaSlug: 'res',
    modoVenta: 'unit',
    medida: 'kg',
    precio: '',
    precioCompra: '',
    cantidadInicial: '',
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

  protected async guardarAlta(): Promise<void> {
    const f = this.formulario();
    if (!f.nombre.trim()) {
      this.errores.set('El nombre es obligatorio.');
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