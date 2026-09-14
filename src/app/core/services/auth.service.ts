import { Injectable, inject, signal } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import type { Perfil, ResultadoOperacion } from '../modelos/operaciones';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly supabase = inject(SupabaseService);
  private readonly client: SupabaseClient | null = this.supabase.client;

  readonly sesion = signal<Perfil | null>(null);
  readonly lista = signal(false);
  readonly existeJefe = signal(false);

  private listoResolver!: () => void;
  private readonly listoPromise = new Promise<void>((r) => (this.listoResolver = r));

  constructor() {
    if (!this.client) {
      this.lista.set(true);
      this.listoResolver();
      return;
    }
    void this.inicializar();
  }

  private async inicializar(): Promise<void> {
    const client = this.client;
    if (!client) return;
    const { data } = await client.auth.getSession();
    if (data.session) await this.cargarPerfil(data.session.user.id);
    await this.cargarExisteJefe();
    this.lista.set(true);
    this.listoResolver();

    client.auth.onAuthStateChange((_evento, sesionNueva) => {
      if (!sesionNueva) this.sesion.set(null);
      else void this.cargarPerfil(sesionNueva.user.id);
    });
  }

  async cuandoListo(): Promise<void> {
    await this.listoPromise;
  }

  get conectado(): boolean {
    return this.client !== null;
  }

  async iniciar(email: string, password: string): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.auth.signInWithPassword({ email, password });
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.recargarPerfil();
    return { ok: true, error: null };
  }

  async registrar(
    nombre: string,
    email: string,
    password: string,
    rol: 'jefe' | 'carnicero',
  ): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { data, error } = await this.client.auth.signUp({
      email,
      password,
      options: { data: { nombre, rol: 'carnicero' } },
    });
    if (error) return { ok: false, error: this.legible(error.message) };
    if (!data.session) return { ok: false, error: 'Revisa tu correo para confirmar la cuenta' };
    await this.cargarPerfil(data.session.user.id);
    if (rol === 'jefe') {
      const reclamado = await this.reclamarJefe();
      if (!reclamado.ok) return reclamado;
    }
    return { ok: true, error: null };
  }

  async reclamarJefe(): Promise<ResultadoOperacion> {
    if (!this.client) return { ok: false, error: 'Sin backend' };
    const { error } = await this.client.rpc('reclamar_jefe');
    if (error) return { ok: false, error: this.legible(error.message) };
    await this.recargarPerfil();
    return { ok: true, error: null };
  }

  async salir(): Promise<void> {
    this.sesion.set(null);
    if (this.client) await this.client.auth.signOut();
  }

  private async recargarPerfil(): Promise<void> {
    if (!this.client) return;
    const { data } = await this.client.auth.getSession();
    if (data.session) await this.cargarPerfil(data.session.user.id);
  }

  private async cargarPerfil(uid: string): Promise<void> {
    if (!this.client || !uid) return;
    const { data } = await this.client
      .from('profiles')
      .select('id, nombre, rol')
      .eq('id', uid)
      .maybeSingle();
    this.sesion.set((data as Perfil | null) ?? null);
  }

  private async cargarExisteJefe(): Promise<void> {
    if (!this.client) return;
    const { data } = await this.client.rpc('existe_jefe');
    if (data !== null) this.existeJefe.set(data as boolean);
  }

  private legible(mensaje: string): string {
    if (/invalid login credentials/i.test(mensaje)) return 'Correo o contraseña incorrectos';
    if (/already registered/i.test(mensaje)) return 'Ese correo ya está registrado';
    if (/jefe en la carniceria/i.test(mensaje)) return 'Ya existe un jefe en la carnicería';
    if (/email not confirmed/i.test(mensaje)) return 'Confirma tu correo antes de entrar';
    if (/password/i.test(mensaje)) return 'La contraseña debe tener al menos 6 caracteres';
    return mensaje;
  }
}