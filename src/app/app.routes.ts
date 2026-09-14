import { Routes } from '@angular/router';
import { sesionActiva, sesionInactiva } from './core/guards/sesion.guard';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () => import('./features/pos/pos.component').then((m) => m.PosComponent),
    canActivate: [sesionActiva],
  },
  {
    path: 'inventario',
    loadComponent: () =>
      import('./features/inventario/inventario.component').then((m) => m.InventarioComponent),
    canActivate: [sesionActiva],
  },
  {
    path: 'mermas',
    loadComponent: () =>
      import('./features/mermas/mermas.component').then((m) => m.MermasComponent),
    canActivate: [sesionActiva],
  },
  {
    path: 'caja',
    loadComponent: () => import('./features/caja/caja.component').then((m) => m.CajaComponent),
    canActivate: [sesionActiva],
  },
  {
    path: 'acceso',
    loadComponent: () =>
      import('./features/acceso/acceso.component').then((m) => m.AccesoComponent),
    canActivate: [sesionInactiva],
  },
  {
    path: 'pos',
    redirectTo: '',
    pathMatch: 'full',
  },
  { path: '**', redirectTo: '' },
];