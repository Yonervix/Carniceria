import { inject } from '@angular/core';
import { Router, type UrlTree } from '@angular/router';
import { AuthService } from '../services/auth.service';

export const sesionActiva = async (): Promise<boolean | UrlTree> => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await auth.cuandoListo();
  return auth.sesion() ? true : router.createUrlTree(['/acceso']);
};

export const sesionInactiva = async (): Promise<boolean | UrlTree> => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await auth.cuandoListo();
  return auth.sesion() ? router.createUrlTree(['/']) : true;
};

export const soloJefe = async (): Promise<boolean | UrlTree> => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await auth.cuandoListo();
  return auth.sesion()?.rol === 'jefe' ? true : router.createUrlTree(['/']);
};