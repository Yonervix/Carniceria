-- ============================================================
--  CORTE · Carnicería boutique · Datos de demostración (BLOQUE 2)
--  Ejecutar DESPUÉS de schema.sql en el SQL Editor.
--  Idempotente: puede re-ejecutarse sin duplicar.
-- ============================================================

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select
  'Solomillo de res',
  'Filete magro, madurado 21 días',
  id,
  'weight',
  'kg',
  42.90,
  28.50
from public.categories
where slug = 'res'
  and not exists (select 1 from public.products where nombre = 'Solomillo de res');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select
  'Picaña',
  'Corte jugoso cercano a la cola, de untuosa infiltración',
  id,
  'weight',
  'kg',
  24.00,
  15.00
from public.categories
where slug = 'res'
  and not exists (select 1 from public.products where nombre = 'Picaña');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Chuletón de res', null, id, 'weight', 'kg', 31.50, 20.00
from public.categories
where slug = 'res'
  and not exists (select 1 from public.products where nombre = 'Chuletón de res');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Lomo ancho', null, id, 'weight', 'kg', 22.75, 14.50
from public.categories
where slug = 'res'
  and not exists (select 1 from public.products where nombre = 'Lomo ancho');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Carne molida especial', 'Molida al momento, 80/20', id, 'weight', 'kg', 18.90, 12.00
from public.categories
where slug = 'res'
  and not exists (select 1 from public.products where nombre = 'Carne molida especial');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Chuletas de cerdo', null, id, 'weight', 'kg', 16.50, 10.00
from public.categories
where slug = 'cerdo'
  and not exists (select 1 from public.products where nombre = 'Chuletas de cerdo');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Costilla de cerdo', null, id, 'weight', 'kg', 14.90, 9.00
from public.categories
where slug = 'cerdo'
  and not exists (select 1 from public.products where nombre = 'Costilla de cerdo');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Tocino ahumado', 'Curado y ahumado en frío', id, 'weight', 'kg', 19.25, 11.00
from public.categories
where slug = 'cerdo'
  and not exists (select 1 from public.products where nombre = 'Tocino ahumado');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Pechuga de pollo', null, id, 'weight', 'kg', 8.90, 5.50
from public.categories
where slug = 'pollo'
  and not exists (select 1 from public.products where nombre = 'Pechuga de pollo');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Muslos de pollo', 'Enteros, con piel', id, 'weight', 'kg', 6.75, 4.00
from public.categories
where slug = 'pollo'
  and not exists (select 1 from public.products where nombre = 'Muslos de pollo');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Pollo entero', null, id, 'unit', null, 5.95, 3.50
from public.categories
where slug = 'pollo'
  and not exists (select 1 from public.products where nombre = 'Pollo entero');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Chorizo artesanal', 'Ahumado, receta de la casa', id, 'unit', null, 3.50, 2.00
from public.categories
where slug = 'elaborados'
  and not exists (select 1 from public.products where nombre = 'Chorizo artesanal');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Hamburguesa casera', null, id, 'unit', null, 4.50, 2.80
from public.categories
where slug = 'elaborados'
  and not exists (select 1 from public.products where nombre = 'Hamburguesa casera');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Morcilla', 'Embutido artesanal', id, 'unit', null, 2.25, 1.50
from public.categories
where slug = 'elaborados'
  and not exists (select 1 from public.products where nombre = 'Morcilla');

insert into public.products (nombre, descripcion, categoria_id, modo_venta, medida, precio, precio_compra)
select 'Caldo de hueso', 'Reducido, ideal para consomé', id, 'unit', null, 6.00, 3.00
from public.categories
where slug = 'elaborados'
  and not exists (select 1 from public.products where nombre = 'Caldo de hueso');

update public.inventory set cantidad = 3.250, stock_minimo = 1.500, ubicacion = 'Vitrina A'
where producto_id = (select id from public.products where nombre = 'Solomillo de res');

update public.inventory set cantidad = 0.800, stock_minimo = 1.200, ubicacion = 'Vitrina A'
where producto_id = (select id from public.products where nombre = 'Picaña');

update public.inventory set cantidad = 6.000, stock_minimo = 2.000, ubicacion = 'Vitrina A'
where producto_id = (select id from public.products where nombre = 'Chuletón de res');

update public.inventory set cantidad = 4.500, stock_minimo = 1.500, ubicacion = 'Vitrina B'
where producto_id = (select id from public.products where nombre = 'Lomo ancho');

update public.inventory set cantidad = 8.000, stock_minimo = 3.000, ubicacion = 'Mostrador 2'
where producto_id = (select id from public.products where nombre = 'Carne molida especial');

update public.inventory set cantidad = 5.400, stock_minimo = 2.000, ubicacion = 'Vitrina B'
where producto_id = (select id from public.products where nombre = 'Chuletas de cerdo');

update public.inventory set cantidad = 0.000, stock_minimo = 2.000, ubicacion = 'Vitrina B'
where producto_id = (select id from public.products where nombre = 'Costilla de cerdo');

update public.inventory set cantidad = 2.100, stock_minimo = 1.000, ubicacion = 'Repisa'
where producto_id = (select id from public.products where nombre = 'Tocino ahumado');

update public.inventory set cantidad = 7.350, stock_minimo = 3.000, ubicacion = 'Vitrina C'
where producto_id = (select id from public.products where nombre = 'Pechuga de pollo');

update public.inventory set cantidad = 9.000, stock_minimo = 4.000, ubicacion = 'Vitrina C'
where producto_id = (select id from public.products where nombre = 'Muslos de pollo');

update public.inventory set cantidad = 8.000, stock_minimo = 3.000, ubicacion = 'Vitrina C'
where producto_id = (select id from public.products where nombre = 'Pollo entero');

update public.inventory set cantidad = 24.000, stock_minimo = 8.000, ubicacion = 'Repisa'
where producto_id = (select id from public.products where nombre = 'Chorizo artesanal');

update public.inventory set cantidad = 12.000, stock_minimo = 6.000, ubicacion = 'Cámara'
where producto_id = (select id from public.products where nombre = 'Hamburguesa casera');

update public.inventory set cantidad = 6.000, stock_minimo = 4.000, ubicacion = 'Repisa'
where producto_id = (select id from public.products where nombre = 'Morcilla');

update public.inventory set cantidad = 5.000, stock_minimo = 2.000, ubicacion = 'Cámara'
where producto_id = (select id from public.products where nombre = 'Caldo de hueso');