export type ModoVenta = 'weight' | 'unit';
export type Medida = 'kg' | 'lb';

export interface ProductoCatalogo {
  id: string;
  nombre: string;
  descripcion: string | null;
  modo_venta: ModoVenta;
  medida: Medida | null;
  precio: number;
  categoria: string;
  categoria_nombre: string | null;
  cantidad: number;
  minimo: number;
  ubicacion: string | null;
  en_minimo: boolean;
}

export interface TicketItem {
  productoId: string;
  nombre: string;
  modo_venta: ModoVenta;
  medida: Medida | null;
  precio: number;
  cantidad: number;
  subtotal: number;
}

export const redondear = (n: number): number => Math.round(n * 100) / 100;