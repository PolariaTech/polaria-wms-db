# Changelog — polaria-wms-db

Versión de producto alineada con Polaria WMS.

## 2.9.17 — 2026-10-08

- Migración **099**: `orden_venta_linea.match_producto` jsonb (texto del cliente, sugerencia Mateo, elección del usuario).

## 2.9.16 — 2026-10-07

- Migración **098**: `bot_materializar_ov_desde_origen` también copia entrega (ventana, dirección, teléfono, andén, notas, prioridad) desde `origen_correo` a la cabecera de la OV.
- Migración **097**: al insertar/actualizar `origen_correo` en OV `por_confirmar`, materializa cabecera desde el JSON (trigger `trg_bot_materializar_ov_origen`). Las líneas las interpreta Mateo al abrir.

## 2.9.12 — 2026-10-06

- Migración **089**: estados `alistamiento` y `alistada` en `estado_orden_venta`.
- `jwt_expiry` local: **604800** (7 días, máximo Supabase); sesión WMS 7 días (alineado a jwt_expiry).

## 2.8.20 — 2026-10-01

- Migración **087**: `origen_correo` jsonb en `orden_venta`.
- Migración **088**: surtido/captura por orden de trabajo (`id_orden_trabajo` / OT).

## 2.8.12 — 2026-09-30

- Migración **087**: `origen_correo` jsonb en `orden_venta` (órdenes de trabajo hijas desde correo/PDF).

## 2.7.15 — 2026-09-25

- Migración **084**: `usuario_reporte_embed` (permisos de reportes por usuario) + `reporte_id` obligatorio en `cuenta_reporte_embed`.
- Migración **085**: `tmp_producto_mas_vendido` (ranking temporal para filtros de exportación de precios).
- Migración **086**: `tmp_grupo_perteneciente` (catálogo temporal de grupos por cuenta).
- Seed de prueba Tecno: grupos pertenecientes.
- Verificación manual: aplicar migraciones 084→086, confirmar tablas/constraints; correr `seeds/seed-tecno-grupos-prueba.sql` y revisar filas en `tmp_grupo_perteneciente` / `comprador.grupo` (cuenta Tecno). Resultado: PASS.

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
