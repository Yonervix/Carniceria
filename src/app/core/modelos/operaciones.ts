export interface CajaEstado {
  id: string;
  fecha: string;
  abierta: boolean;
  efectivo_inicial: number;
  ventas_total: number;
  efectivo_cobrado: number;
  digital_cobrado: number;
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
  id?: string | null;
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
  imagenUrl: string;
}

export interface EditarProducto {
  id: string;
  nombre: string;
  descripcion: string;
  categoriaSlug: string;
  modoVenta: 'weight' | 'unit';
  medida: string;
  precio: number;
  precioCompra: number | null;
  imagenUrl: string;
  stockMinimo: number;
  stockActual: number | null;
  ubicacion: string;
  activo: boolean;
}

export interface ItemVentaHistorial {
  nombre: string;
  cantidad: number;
  medida?: string;
  precio?: number;
  subtotal: number;
}

export type MetodoPago = 'efectivo' | 'tarjeta' | 'transferencia';

export interface PagoVenta {
  metodo: MetodoPago;
  monto: number;
}

export interface VentaHistorial {
  id: string;
  subtotal: number;
  anulada: boolean;
  created_at: string;
  carnicero: string;
  cliente_id: string | null;
  cliente: string | null;
  articulos: ItemVentaHistorial[];
  pagos: PagoVenta[];
  motivo_anulacion?: string | null;
  vuelto?: number;
  efectivo_recibido?: number | null;
}

export interface Cliente {
  id: string;
  nombre: string;
  telefono: string | null;
  saldo: number;
  created_at?: string;
}

export interface VentaCliente {
  id: string;
  subtotal: number;
  anulada: boolean;
  motivo_anulacion: string | null;
  created_at: string;
  carnicero: string;
  articulos: ItemVentaHistorial[];
  pagos: PagoVenta[];
}

export interface AbonoCliente {
  id: string;
  monto: number;
  metodo: MetodoPago;
  nota: string | null;
  created_at: string;
}

export interface ReporteResumen {
  desde: string;
  hasta: string;
  ventas: number;
  facturado: number;
  a_credito: number;
  anulado: number;
  efectivo: number;
  tarjeta: number;
  transferencia: number;
  abonos: number;
}

export interface FilaDia {
  fecha: string;
  ventas: number;
  facturado: number;
  a_credito: number;
  anulado: number;
  efectivo: number;
  digital: number;
}

export interface FilaCarnicero {
  carnicero: string;
  ventas: number;
  cobrado: number;
  a_credito: number;
  facturado: number;
}

export interface FilaMetodo {
  metodo: string;
  monto: number;
}

export interface FilaTopProducto {
  nombre: string;
  medida: string;
  cantidad: number;
  total: number;
}

export interface TurnoCajaHistorial {
  id: string;
  fecha: string;
  abierta: boolean;
  efectivo_inicial: number;
  ventas_total: number;
  efectivo_cobrado: number;
  digital_cobrado: number;
  abierta_at: string;
  cerrada_at: string | null;
  efectivo_final: number | null;
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