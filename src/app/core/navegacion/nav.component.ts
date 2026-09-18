import { Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { CajaService } from '../services/caja.service';
import { AuthService } from '../services/auth.service';
import { alternarTema, aplicarTemaInicial, seguirSistema } from '../utilidades/tema';

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

  protected readonly estadoCaja = this.cajaService.estado;
  protected readonly cajaConectada = this.cajaService.conectado;
  protected readonly sesion = this.auth.sesion;
  protected readonly oscuro = signal(false);

  protected readonly enlaces = computed<Enlace[]>(() => {
    const generales: Enlace[] = [
      { ruta: '/', etiqueta: 'Despacho', exacto: true, icono: 'despacho' },
      { ruta: '/inventario', etiqueta: 'Inventario', exacto: false, icono: 'inventario' },
      { ruta: '/cuentas', etiqueta: 'Cuentas', exacto: false, icono: 'cuentas' },
      { ruta: '/caja', etiqueta: 'Caja', exacto: false, icono: 'caja' },
    ];
    if (this.sesion()?.rol === 'jefe') {
      generales.splice(2, 0, { ruta: '/mermas', etiqueta: 'Mermas', exacto: false, icono: 'mermas' });
      generales.splice(3, 0, { ruta: '/reportes', etiqueta: 'Reportes', exacto: false, icono: 'reportes' });
    }
    return generales;
  });

  protected readonly estadoCajaUi = computed(() => {
    const c = this.estadoCaja();
    if (!c) return 'sin-caja';
    return c.abierta ? 'abierta' : 'cerrada';
  });

  constructor() {
    this.oscuro.set(aplicarTemaInicial());
    seguirSistema((o) => this.oscuro.set(o));
  }

  protected alternarOscuro(): void {
    this.oscuro.set(alternarTema(this.oscuro()));
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