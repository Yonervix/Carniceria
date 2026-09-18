const CLAVE = 'corte-tema';

function detectarSistema(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-color-scheme: dark)').matches
  );
}

export function guardadoTema(): 'oscuro' | 'claro' | null {
  if (typeof localStorage === 'undefined') return null;
  const valor = localStorage.getItem(CLAVE);
  return valor === 'oscuro' || valor === 'claro' ? valor : null;
}

export function aplicarTemaInicial(): boolean {
  const guardado = guardadoTema();
  const oscuro = guardado === null ? detectarSistema() : guardado === 'oscuro';
  document.documentElement.classList.toggle('dark', oscuro);
  return oscuro;
}

export function alternarTema(actual: boolean): boolean {
  const proximo = !actual;
  document.documentElement.classList.toggle('dark', proximo);
  if (typeof localStorage !== 'undefined') {
    localStorage.setItem(CLAVE, proximo ? 'oscuro' : 'claro');
  }
  return proximo;
}

export function seguirSistema(enCambio: (oscuro: boolean) => void): void {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  const handler = (e: MediaQueryListEvent): void => {
    if (guardadoTema() !== null) return;
    document.documentElement.classList.toggle('dark', e.matches);
    enCambio(e.matches);
  };
  if (typeof mq.addEventListener === 'function') mq.addEventListener('change', handler);
}