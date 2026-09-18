import { Component, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';
import { AvisoService } from '../../core/services/aviso.service';
import { aplicarTemaInicial } from '../../core/utilidades/tema';
import type { ResultadoOperacion } from '../../core/modelos/operaciones';

type ModoAcceso = 'crear' | 'entrar';

@Component({
  selector: 'app-acceso',
  templateUrl: './acceso.component.html',
})
export class AccesoComponent {
  private readonly auth = inject(AuthService);
  private readonly aviso = inject(AvisoService);
  private readonly router = inject(Router);

  protected readonly existeJefe = this.auth.existeJefe;
  protected readonly modo = signal<ModoAcceso>('crear');
  protected readonly nombre = signal('');
  protected readonly email = signal('');
  protected readonly password = signal('');
  protected readonly reclamar = signal(false);
  protected readonly enviando = signal(false);
  protected readonly error = signal('');
  protected readonly listo = this.auth.lista;

  constructor() {
    aplicarTemaInicial();
  }

  protected electronica(): void {
    this.modo.update((m) => (m === 'crear' ? 'entrar' : 'crear'));
    this.error.set('');
  }

  protected campo(campo: 'email' | 'password' | 'nombre', valor: string): void {
    if (campo === 'email') this.email.set(valor);
    if (campo === 'password') this.password.set(valor);
    if (campo === 'nombre') this.nombre.set(valor);
  }

  protected async guardar(): Promise<void> {
    const email = this.email().trim().toLowerCase();
    const password = this.password();
    const creando = this.modo() === 'crear';

    if (!email || password.length < 6) {
      this.error.set('Correo y contraseña (mínimo 6 caracteres) son obligatorios.');
      return;
    }
    if (creando && !this.nombre().trim()) {
      this.error.set('Escribe tu nombre.');
      return;
    }

    this.enviando.set(true);
    this.error.set('');

    let res: ResultadoOperacion;
    if (!creando) {
      res = await this.auth.iniciar(email, password);
    } else {
      const rol = this.reclamar() && !this.existeJefe() ? 'jefe' : 'carnicero';
      res = await this.auth.registrar(this.nombre().trim(), email, password, rol);
    }

    this.enviando.set(false);

    if (!res.ok) {
      this.error.set(res.error ?? 'No se pudo completar.');
      return;
    }
    this.aviso.mostrar(creando ? 'Cuenta creada · bienvenido a CORTE' : 'Sesión iniciada', 'ok');
    this.router.navigate(['/']);
  }
}