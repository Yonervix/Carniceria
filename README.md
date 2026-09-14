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
│  ├─ styles.css                   Base del sistema, dark overrides, .tecla/.chip/.nav-activo
│  ├─ environments/environment.ts  supabaseUrl + anonKey (en blanco hasta conectar)
│  └─ app/
│     ├─ app.ts                    Root: <router-outlet /> + <app-aviso />
│     ├─ app.routes.ts             '' (POS) · /inventario · /mermas · /caja
│     ├─ core/
│     │  ├─ modelos/catalogo.ts    ProductoCatalogo, TicketItem, redondear, redondearPeso
│     │  ├─ modelos/operaciones.ts CajaEstado, VentaRegistrada, MovimientoReciente, payloads
│     │  ├─ servicios/supabase.service.ts    Cliente (null si no hay URL)
│     │  ├─ servicios/catalogo.service.ts    Catálogo vivo (inventario_vivo) + Realtime
│     │  ├─ servicios/caja.service.ts        Caja del día, ventas, RPCs abrir/cerrar/vender
│     │  ├─ servicios/stock.service.ts       Merma, desposte, movimientos recientes
│     │  ├─ servicios/aviso.service.ts       Toast global (ok/info/err)
│     │  └─ navegacion/nav.component.ts      Marca, links, chip de caja, toggle tema
│     └─ features/
│        ├─ pos/pos.component.*          Despacho táctil + ticket + pesaje
│        ├─ pos/pesaje.component.*        Keypad Precio x Peso (3 decimales)
│        ├─ inventario/inventario.*       Stock vivo con alertas buey
│        ├─ mermas/mermas.*               Mermas + desposte + ledger
│        └─ caja/caja.*                   Apertura, ventas y cierre del turno
└─ supabase/
   ├─ schema.sql                  Bloques 1-3 concatenados (idempotente)
   └─ seed.sql                    Catálogo de demostración (15 cortes)
```

---

## 4. Lo que ya funciona (hecho)

### Bloque 1 — Estructura de datos
- `profiles` (rol `jefe`/`carnicero`, autoperfil al crear usuario).
- `categories` (res, cerdo, pollo, elaborados), `products` (`modo_venta weight|unit` con constraint de `medida kg|lb`).
- `inventory` (`cantidad numeric(10,3)`, `stock_minimo`, `ubicacion`, autopory por trigger).
- `inventory_movements` (ledger auditado con `saldo`).
- Vista `inventario_vivo` con `en_minimo` + Realtime en inventory/products.
- RLS completa + RPC `ajustar_existencia` (solo jefe).

### Bloque 2 — Módulo de caja / despacho táctil
- Catálogo de dos columnas con pills de categoría, precio mono `/kg`, badge báscula|caja, indicador buey en stock mínimo y agotados atenuados.
- Flujo de pesaje: tocar un producto `weight` abre un keypad 3x4 con display masivo mono, total vivo `Peso x Precio`, máx. 3 decimales, bloqueo si excede stock y atajos de teclado.
- Ticket lateral con fusion de líneas, subtotales mono y total Oliva `text-4xl tabular`.
- Estados: skeleton, "Primera carga" (sin backend), sin acceso, catálogo vacío.
- `seed.sql` con 15 cortes demo (Picaña en mínimo, Costilla agotada).
- Verificado: `ng build` compila sin errores.

---

## 5. Lo que hará el Bloque 3 (en curso)

Todas las escrituras por RPC, todo idempotente y concatenado al final de `schema.sql`.

1. **Nuevas tablas**: `caja` (única por `fecha`), `ventas` + `venta_items`, `desposte` + `desposte_items`. Con RLS.
2. **RPCs** (security definer):
   - `abrir_caja(p_efectivo_inicial)` / `cerrar_caja(p_efectivo_final)` — solo jefe.
   - `registrar_venta(p_items jsonb)` — valida caja abierta, descuenta stock a precio de BD, registra items y actualiza `caja.ventas_total`.
   - `registrar_merma(p_producto_id, p_cantidad, p_nota)` — cualquier empleado autenticado.
   - `registrar_desposte(p_origen_id, p_peso_origen, p_destinos jsonb, p_nota)` — jefe; desconta origen y acredita destinos, suma de destinos <= peso origen.
   - `aplicar_movimiento(...)` helper interno que centraliza el descuento + ledger y evita saldos negativos.
3. **Vista de inventario vivo** (`/inventario`): filas con alerta sutil Rojo-Buey en stock mínimo, filtros (todo / en mínimo / agotados), buscador y stats.
4. **Mermas y desposte** (`/mermas`): formulario de merma y conversión pieza-origen => cortes destino, con vista de movimientos recientes.
5. **Caja diaria** (`/caja`): apertura, ventas del día en tiempo real y cierre de turno con diferencia (esperado vs contado) en Verde Oliva Crudo.
6. **POS conectado**: el botón `Cobrar` llama a `registrar_venta`, exige caja abierta y muestra el chip de estado de caja.
7. Navegación superior compartida (`NavComponent`) entre Despacho / Inventario / Mermas / Caja.

---

## 6. Próximos bloques (hoja de ruta)

- **Bloque 4 — Acceso y sesión**
  - Pantalla de inicio de sesión (Supabase Auth), perfil con rol y gestión de carniceros (jefe).
  - Protección de rutas por rol (`jefe`/`carnicero`).
- **Bloque 5 — Administración de catálogo**
  - Alta/edición de productos y categorías, precios de compra/venta, stock mínimo y ubicación.
  - Ajuste de inventario, órdenes de compra y entradas.
- **Bloque 6 — Reportes**
  - Cierre por producto, ventas por carnicero, mermas y conversiones, tendencias y valor de vitrina (Verde Oliva).
  - Exportación (PDF/CSV) de reportes del día.
- **Bloque 7 — Publicación**
  - Configuración de Vercel + variables de entorno, contraseña maestra de Supabase, guardado.

---

## 7. Cómo correrlo

```bash
npm install
npm start          # dev en http://localhost:4200
npx ng build       # compilar a dist/
```

### Conectar Supabase
1. Crear proyecto en supabase.com.
2. Abrir **SQL Editor** y ejecutar `supabase/schema.sql` y después `supabase/seed.sql`.
3. Copiar `Project URL` y `anon public key` a `src/environments/environment.ts`.
4. Crear un usuario en Auth; su perfil se crea solo (rol por defecto `carnicero`; para roles `jefe`, editar la fila en `profiles`).

> Sin credenciales la app funciona en modo "Primera carga": los estados y el diseño se ven, pero no hay datos.

---

## 8. Reglas de arquitectura (importantes al continuar)

- No editar lo ya entregado de `schema.sql` sin necesidad: **los bloques nuevos se concatenan al final**.
- Nunca mutar `inventory`, `caja` o `ventas` directo desde el cliente: solo por RPC.
- Una única vista fuente de catálogo: `inventario_vivo` (sobre `products` activos).
- Rounding: pesos en `redondearPeso` (3 decimales), dinero en `redondear` (2).
- `environment.ts` en blanco = `client` null = estados "Primera carga"; todos los servicios deben guardarlo.
- Realtime: un canal por dominio (`corte-stock-vivo`, `corte-caja-vivo`).