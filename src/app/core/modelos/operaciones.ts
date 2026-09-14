export interface CajaEstado {
  id: string;
  fecha: string;
  abierta: boolean;
  efectivo_inicial: number;
  ventas_total: number;
  abierta_at: string;
  cerrada_at: string | null;
  efectivo_final: number | null;
}

export interface VentaRegistrada {
  id: string;
  caja_id: string;
  subtotal: number;
  created_at: string;
}

export interface MovimientoReciente {
  id: number;
  nombre: string;
  concepto: string;
  cambio: number;
  saldo: number;
  nota: string | null;
  created_at: string;
}

export interface ItemVentaPayload {
  producto_id: string;
  cantidad: number;
}

export interface ItemDespostePayload {
  producto_id: string;
  peso: number;
}

export interface ResultadoOperacion {
  ok: boolean;
  error: string | null;
}

export interface AltaProducto {
  nombre: string;
  descripcion: string;
  categoriaSlug: string;
  modoVenta: 'weight' | 'unit';
  medida: string;
  precio: number;
  precioCompra: number;
  cantidadInicial: number;
}

export type RolUsuario = 'jefe' | 'carnicero';

export interface Perfil {
  id: string;
  nombre: string;
  rol: RolUsuario;
}

export type TipoAviso = 'ok' | 'info' | 'err';

export interface Aviso {
  texto: string;
  tipo: TipoAviso;
}