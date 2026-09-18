import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import { environment } from '../../../environments/environment';
import type { ProductoCatalogo } from '../modelos/catalogo';
import type { AltaProducto, EditarProducto, ResultadoOperacion } from '../modelos/operaciones';

export interface Categoria {
  slug: string;
  nombre: string;
}

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private readonly supabase = inject(SupabaseService);
  private readonly client: SupabaseClient | null = this.supabase.client;

  readonly productos = signal<ProductoCatalogo[]>([]);
  readonly categorias = signal<Categoria[]>([]);
  readonly cargando = signal(false);
  readonly sinBackend = signal(false);
  readonly error = signal('');

  constructor() {
    if (!this.client) {
      this.sinBackend.set(true);
      return;
    }
    void this.sincronizar();
    this.suscribir();
  }

  get conectado(): boolean {
    return this.client !== null;
  }

  async sincronizar(): Promise<void> {
    if (!this.client) return;
    this.cargando.set(true);
    const { data, error } = await this.client
      .from('inventario_vivo')
      .select('*')
      .order('categoria', { ascending: true })
      .order('nombre', { ascending: true });

    if (error) {
      this.error.set(error.message);
      this.cargando.set(false);
      return;
    }
    this.productos.set((data ?? []) as ProductoCatalogo[]);
    this.error.set('');
    this.cargando.set(false);
    await this.cargarCategorias();
  }

  private async cargarCategorias(): Promise<void> {
    if (!this.client) return;
    const { data } = await this.client
      .from('categories')
      .select('slug, nombre')
      .order('orden', { ascending: true });
    if (data) this.categorias.set(data as Categoria[]);
  }

  async altaProducto(p: AltaProducto): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('registrar_alta_producto', {
      p_nombre: p.nombre.trim(),
      p_descripcion: p.descripcion.trim() || null,
      p_categoria_slug: p.categoriaSlug,
      p_modo_venta: p.modoVenta,
      p_medida: p.medida || null,
      p_precio: p.precio,
      p_precio_compra: p.precioCompra > 0 ? p.precioCompra : null,
      p_cantidad_inicial: p.cantidadInicial,
      p_imagen_url: p.imagenUrl.trim() || null,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    return { ok: true, error: null };
  }

  async crearCategoria(nombre: string): Promise<ResultadoOperacion & { slug?: string }> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { data, error } = await this.client.rpc('registrar_categoria', {
      p_nombre: nombre.trim(),
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.cargarCategorias();
    return { ok: true, error: null, slug: (data as string | null) ?? undefined };
  }

  async costoDe(id: string): Promise<number> {
    if (!this.client) return 0;
    const { data } = await this.client
      .from('products')
      .select('precio_compra')
      .eq('id', id)
      .maybeSingle();
    const fila = data as { precio_compra: number | null } | null;
    return fila && fila.precio_compra ? Number(fila.precio_compra) : 0;
  }

  async actualizarProducto(p: EditarProducto): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('actualizar_producto', {
      p_producto_id: p.id,
      p_nombre: p.nombre.trim(),
      p_descripcion: p.descripcion.trim() || null,
      p_categoria_slug: p.categoriaSlug,
      p_modo_venta: p.modoVenta,
      p_medida: p.modoVenta === 'weight' ? p.medida : null,
      p_precio: p.precio,
      p_precio_compra: p.precioCompra ?? null,
      p_imagen_url: p.imagenUrl.trim() || null,
      p_stock_minimo: p.stockMinimo > 0 ? p.stockMinimo : null,
      p_stock_actual: p.stockActual,
      p_ubicacion: p.ubicacion.trim() || null,
      p_activo: p.activo,
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    return { ok: true, error: null };
  }

  private legible(mensaje: string): string {
    if (/jefe da de alta|jefe puede editar|jefe crea categorias/i.test(mensaje))
      return 'Solo el jefe puede hacer esta acción';
    if (/nombre es obligatorio|nombre de la categoria/i.test(mensaje)) return 'El nombre es obligatorio';
    if (/ya existe un producto/i.test(mensaje)) return 'Ya existe un producto con ese nombre';
    if (/categoria invalida/i.test(mensaje)) return 'Categoría inválida';
    if (/medida/i.test(mensaje)) return 'Un producto por peso necesita kg o lb';
    if (/negativos/i.test(mensaje)) return 'Los precios no pueden ser negativos';
    return mensaje;
  }

  suscribir(): void {
    if (!this.client || !environment.supabaseUrl) return;
    this.client
      .channel('corte-stock-vivo')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'inventory' },
        () => void this.sincronizar(),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'products' },
        () => void this.sincronizar(),
      )
      .subscribe();
  }
}