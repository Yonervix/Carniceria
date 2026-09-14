import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import { environment } from '../../../environments/environment';
import type { ProductoCatalogo } from '../modelos/catalogo';

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private readonly supabase = inject(SupabaseService);
  private client: SupabaseClient | null;

  readonly productos = signal<ProductoCatalogo[]>([]);
  readonly cargando = signal(false);
  readonly sinBackend = signal(false);
  readonly error = signal('');

  constructor() {
    this.client = this.supabase.client;
    this.sincronizar();
  }

  get conectado(): boolean {
    return this.client !== null;
  }

  async sincronizar(): Promise<void> {
    if (!this.client) {
      this.sinBackend.set(true);
      this.cargando.set(false);
      return;
    }
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
  }

  suscribir(): void {
    if (!this.client || !environment.supabaseUrl) return;
    this.cargando.set(true);

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