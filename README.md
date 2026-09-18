# CORTE

POS + inventario para una **carnicería boutique** construido por bloques, con estética **Artisanal Tech**.

UI en español, tipografía Geist / Geist Mono (tabular para precios y pesos), paleta de caliza piedra, Rojo-Buey y Verde Oliva Crudo. Sin emojis: iconografía en SVG inline.

---

## 1. Stack

| Capa       | Tecnología |
| ---------- | ---------- |
| Frontend   | Angular 22 (componentes standalone, signals, control flow `@if/@for`) |
| Estilos    | Tailwind CSS 3.4 (config 100% custom) + PostCSS |
| Tipografía | `@fontsource/geist-sans` + `@fontsource/geist-mono` (autohosted) |
| Backend    | Supabase (Postgres, Realtime, Auth, RLS) |
| Deploy     | Vercel |

**Convenciones**
- Sin comentarios en el código TypeScript.
- Todas las mutaciones de stock/ventas/caja pasan por **RPC** `security definer set search_path = public` (nunca inserts directos desde el cliente).
- SQL idempotente (`create or replace`, `on conflict do nothing`, guards en realtime).
- Verificación: `npx ng build`. No hay suite de tests.
- El SQL Editor de Supabase aborta en el primer error; ejecutar en orden.

---

## 2. Sistema de diseño

- `piedra` (caliza/lineno, **nunca** `#FFF`): 50 `#f6f5f0` ... 900 `#423e35`, 950 `#201e19`.
- `buey` (Rojo-Buey, ancla 900 `#5C1D1D`): CTAs, acciones y estados críticos.
- `oliva` (verde oliva crudo, ancla 600 `#6c7a3b`): totales, ventas y cierres de caja exitosos.
- Sombras tintadas a piedra: `shadow-premium/-sm/-lg`, `shadow-total` (oliva), `shadow-hairline`.
- Radios: `rounded-control` 8px, `rounded-panel` 12px. Easing `ease-soft`.
- Z-index: nav 40 · overlay 50 · modal 60 · aviso 70.
- Dark mode por clase `.dark` en `<html>`, persistido en `localStorage.corte-tema`.
- Formatos mono tabular: peso `1.3-3`, unidades `1.0-0`, dinero `1.2-2` (prefix `$` manual).

---

## 3. Estructura del proyecto

```
corte/
├─ tailwind.config.js              Paleta, fuentes, sombras, easing
├─ angular.json                    Builder application, fuentes Geist autohosted
├─ src/
│  ├─ index.html                   Shell (lenguaje es, favicon)
│  ├─ styles.css                   Base del sistema, dark, .tecla/.chip/.nav-activo, @media print
│  ├─ environments/environment.ts  supabaseUrl + anonKey (en blanco hasta conectar)
│  └─ app/
│     ├─ app.ts                    Root: <router-outlet /> + <app-aviso />
│     ├─ app.routes.ts             '' · /inventario · /caja · /cuentas · /mermas · /reportes · /acceso
│     ├─ core/
│     │  ├─ modelos/               catalogo.ts (ProductoCatalogo, TicketItem) · operaciones.ts (payloads, historiales)
│     │  ├─ utilidades/            tema.ts (dark mode) · negocio.ts (NEGOCIO: nombre/dirección/teléfono del recibo)
│     │  ├─ servicios/             supabase · auth · catalogo · caja · stock · reportes · aviso
│     │  ├─ componentes/           aviso.component.ts (toast global)
│     │  ├─ guards/                sesion.guard.ts (sesionActiva, sesionInactiva, soloJefe)
│     │  └─ navegacion/            nav.component.ts (enlaces por rol + chip de caja + tema)
│     └─ features/
│        ├─ pos/                   Despacho táctil + ticket + pesaje + cobro (efectivo/digital/crédito)
│        ├─ pos/pesaje.component.* Keypad Precio x Peso (3 decimales)
│        ├─ caja/                  Apertura, ventas del día, reabrir, anular (jefe) y recibo por venta
│        ├─ inventario/            Stock vivo, filtros, alta/edición de cortes (jefe) con existencia actual
│        ├─ mermas/                Mermas + desposte + ledger (solo jefe)
│        ├─ cuentas/               Clientes, saldos y abonos
│        ├─ reportes/              Ventas/cortes/mermas del día-ayer-rango (solo jefe) + imprimir
│        ├─ recibo/                Factura térmica (80mm) con folio, pagos, vuelto y reimpresión
│        └─ acceso/                Login/register + "reclamar jefe" de la primera cuenta
└─ supabase/
   ├─ schema.sql                   Bloques 1-14 concatenados (idempotente)
   ├─ seed.sql                     Catálogo de demostración (15 cortes)
   └─ bloque5.sql … bloque14.sql   Bloques sueltos para proyectos ya existentes
```

---

## 4. Lo que ya funciona (bloques completados)

### Bloque 1 — Estructura de datos
- `profiles` (rol `jefe`/`carnicero`, autoperfil al crear usuario), `categories`, `products` (`modo_venta weight|unit`, medida `kg|lb`).
- `inventory` (`cantidad numeric(10,3)`, `stock_minimo`, `ubicacion`) y `inventory_movements` (ledger con `saldo`).
- Vista `inventario_vivo` con `en_minimo` + Realtime en inventory/products.
- RLS completa + RPC `ajustar_existencia` (solo jefe).

### Bloques 2-3 — Despacho, mermas y caja
- Catálogo táctil con pills de categoría, precio mono `/kg`, badge báscula|caja, stock mínimo y agotados.
- Pesaje con keypad (Peso x Precio, 3 decimales, tope de stock).
- Ticket lateral con fusión de líneas y total Oliva; cobro con mezcla de pagos (efectivo/tarjeta/transferencia) y venta a crédito.
- Mermas y desposte con ledger; caja diaria (apertura/cierre, esperado vs contado).
- `registrar_venta` / `registrar_merma` / `registrar_desposte` por RPC, con `aplicar_movimiento` central.

### Bloques 4-7 — Acceso, catálogo administrativo, clientes y permisos
- Login/register con Supabase Auth; la **primera cuenta** se reclama jefe vía `reclamar_jefe()`; rutas protegidas por guard con rol.
- Alta de productos (jefe) con categorías, precio/costo, cantidad inicial y foto.
- Clientes con saldo y abonos (`/cuentas`); venta a crédito suma al saldo y no acepta pagos.
- Edición de producto (jefe): nombre, costo, foto, mínimo, ubicación y **existencia actual** (ajuste con movimiento).
- Permisos: carnicero vende, ve inventario, ve/abona cuentas y abre/cierra/reabre caja; jefe además edita/da de alta, anula ventas, ve historial de caja, mermas y reportes.

### Bloques 8-12 — Caja viva y reportes
- `caja_vivo()` devuelve el turno abierto o el último del día; cash y digital separados.
- Reportes (jefe) por día/ayer/rango: ventas, cortes más vendidos y mermas, con impresión limpia.

### Bloques 13-14 — Factura térmica y ajuste de stock
- Factura imprimible tipo ticket 80mm (folio `R-XXXXXX`, corte con kg/precio, pagos, efectivo recibido y cambio); se muestra al cobrar (no auto-impresión) y se reimprime desde Caja; el nombre/dirección/teléfono se configuran en `core/utilidades/negocio.ts`.
- `actualizar_producto` acepta `p_stock_actual`: al editar, si cambia la existencia se ajusta y se registra como movimiento "Ajuste desde inventario".

**Verificado:** `ng build` compila sin errores.

---

## 5. Cómo correrlo

```bash
npm install
npm start          # dev en http://localhost:4200
npx ng build       # compilar a dist/
```

### Conectar Supabase
1. Crear proyecto en supabase.com.
2. Abrir **SQL Editor** y ejecutar `supabase/schema.sql` (bloques 1-14) y después `supabase/seed.sql`. Si ya tenías el esquema anterior, corre solo los bloques faltantes en orden (`bloque5.sql` … `bloque14.sql`).
3. Copiar `Project URL` y `anon public key` a `src/environments/environment.ts`.
4. Registrar al jefe con la aplicación: la **primera cuenta** tomates el rol `jefe` automáticamente.

> Sin credenciales la app funciona en modo "Primera carga": los estados y el diseño se ven, pero no hay datos.

---

## 6. Pendientes opcionales

- Datos reales del negocio en el recibo (`core/utilidades/negocio.ts`).
- En producción: confirmar el email y que el jefe "reclame" su cuenta (requiere la llave `service_role`, manual desde el dashboard).
- Folio correlativo por día (hoy es código derivado del id de la venta).
- Exportación PDF/CSV de reportes.

---

## 7. Reglas de arquitectura (importantes al continuar)

- No editar lo ya entregado de `schema.sql` sin necesidad: **los bloques nuevos se concatenan al final**.
- Nunca mutar `inventory`, `caja` o `ventas` directo desde el cliente: solo por RPC.
- Una única vista fuente de catálogo: `inventario_vivo` (sobre `products` activos).
- Rounding: pesos en `redondearPeso` (3 decimales), dinero en `redondear` (2).
- `environment.ts` en blanco = `client` null = estados "Primera carga"; todos los servicios deben guardarlo.
- Realtime: un canal por dominio (`corte-stock-vivo`, `corte-caja-vivo`).