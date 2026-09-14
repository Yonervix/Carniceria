import { Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { CajaService } from '../services/caja.service';
import { AuthService } from '../services/auth.service';

interface Enlace {
  ruta: string;
  etiqueta: string;
  exacto: boolean;
  icono: string;
}

@Component({
  selector: 'app-nav',
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './nav.component.html',
})
export class NavComponent {
  private readonly cajaService = inject(CajaService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly claveTema = 'corte-tema';

  protected readonly estadoCaja = this.cajaService.estado;
  protected readonly cajaConectada = this.cajaService.conectado;
  protected readonly sesion = this.auth.sesion;
  protected readonly oscuro = signal(false);

  protected readonly enlaces: Enlace[] = [
    { ruta: '/', etiqueta: 'Despacho', exacto: true, icono: 'despacho' },
    { ruta: '/inventario', etiqueta: 'Inventario', exacto: false, icono: 'inventario' },
    { ruta: '/mermas', etiqueta: 'Mermas', exacto: false, icono: 'mermas' },
    { ruta: '/caja', etiqueta: 'Caja', exacto: false, icono: 'caja' },
  ];

  protected readonly estadoCajaUi = computed(() => {
    const c = this.estadoCaja();
    if (!c) return 'sin-caja';
    return c.abierta ? 'abierta' : 'cerrada';
  });

  constructor() {
    const guardado =
      typeof localStorage !== 'undefined' && localStorage.getItem(this.claveTema) === 'oscuro';
    this.oscuro.set(guardado);
    document.documentElement.classList.toggle('dark', guardado);
  }

  protected alternarOscuro(): void {
    const proximo = !this.oscuro();
    this.oscuro.set(proximo);
    document.documentElement.classList.toggle('dark', proximo);
    localStorage.setItem(this.claveTema, proximo ? 'oscuro' : 'claro');
  }

  protected etiquetaRol(rol: string): string {
    return rol === 'jefe' ? 'Jefe' : 'Carnicero';
  }

  protected inicial(nombre: string): string {
    return (nombre || 'C').trim().charAt(0).toUpperCase();
  }

  protected async salirSesion(): Promise<void> {
    await this.auth.salir();
    this.router.navigate(['/acceso']);
  }
}