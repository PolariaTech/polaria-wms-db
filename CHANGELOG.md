# Changelog — polaria-wms-db

Versión de producto alineada con Polaria WMS.

## 2.7.15 — 2026-09-25

- Migración **084**: `usuario_reporte_embed` (permisos de reportes por usuario) + `reporte_id` obligatorio en `cuenta_reporte_embed`.
- Migración **085**: `tmp_producto_mas_vendido` (ranking temporal para filtros de exportación de precios).
- Migración **086**: `tmp_grupo_perteneciente` (catálogo temporal de grupos por cuenta).
- Seed de prueba Tecno: grupos pertenecientes.

## 2.7.5 — 2026-09-17

- Migración **081**: teléfono único en `usuario`.
- Migración **082**: `cuenta.acceso_wms` / `cuenta.acceso_mateo` (ya no se usan para el login).
- Migración **083**: `usuario.acceso_wms` / `usuario.acceso_mateo`.

## 2.4.9 — 2026-09-03

- Migración 068: `comprador.metadatos_alta`.
- Migración 069: columnas planas del formulario de alta de comprador (+ sync `emp_*`).
- Migración 070: columnas de captura de orden de venta (+ sync `emp_*`).

## 2.4.3 — 2026-08-29

- Migración 067: `comprador_producto_alias` (RLS, clone `emp_*`).
- Serie de migraciones documentada: 001–067.
