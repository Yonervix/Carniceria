import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import { environment } from '../../../environments/environment';
import type { ProductoCatalogo } from '../modelos/catalogo';
import type { AltaProducto, ResultadoOperacion } from '../modelos/operaciones';

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
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    return { ok: true, error: null };
  }

  private legible(mensaje: string): string {
    if (/jefe da de alta/i.test(mensaje)) return 'Solo el jefe da de alta productos';
    if (/nombre es obligatorio/i.test(mensaje)) return 'El nombre es obligatorio';
    if (/ya existe un producto/i.test(mensaje)) return 'Ya existe un producto con ese nombre';
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