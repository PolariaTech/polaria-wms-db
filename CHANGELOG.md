# Changelog — polaria-wms-db

Versión de producto alineada con Polaria WMS.

## Unreleased

- Migración **125**: dos cambios para que dos copias de la API no dupliquen una OV ni pierdan una corrección de OT durante un despliegue (REQ-439 / POL-453). (1) Columna `correo_pedido_ingreso.latido_at` (`timestamptz`, nullable): señal de vida que la copia que procesa un ingreso actualiza cada 15 s; pasados 60 s sin señal el ingreso se considera abandonado y se puede reintentar desde cualquier copia. Las filas anteriores quedan en NULL y usan `updated_at`. Se replica a `template_wms` y a cada `emp_*` con `wms_sync_column_to_tenants` (si existe), y la migración la asegura además en cada esquema que tenga la tabla, porque la API la lee en el esquema de cada empresa. (2) Tabla `public.correo_ot_trabajo`: trabajos de corrección de OT desde el correo, antes un `Map` en memoria de cada copia. Un solo trabajo `procesando` por (`esquema`, OV, usuario) con índice único parcial, `latido_at` propio (3 min sin señal pasa a `error`) y CHECK de coherencia entre `estado` y `terminado_at`. RLS activo, sin políticas y sin permisos para `anon` ni `authenticated`: la API la usa por Prisma. Es idempotente. Prueba en `supabase/tests/125_correo_ingreso_latido_y_trabajos_ot_test.sql`, que corre en el humo SQL de CI. **Orden de despliegue:** se aplica primero; la API v2.13.53 o posterior falla si la columna o la tabla no existen. No se aplica sola: la aplica una persona, y no se reinicia la API durante un ingreso o una corrección en curso.

- Migración **124**: columna `orden_venta_linea.posicion` (`integer`, nullable, sin default) con el lugar de cada línea en la OC de origen (REQ-370). Hoy la tabla no guarda orden: la web lee las líneas sin `ORDER BY` y la API las ordena por un UUID aleatorio, así que la OV mostraba los productos en otro orden que la OC. La web escribe `posicion` al insertar las líneas y la web y la API ordenan por ella con `NULLS LAST`; las líneas anteriores quedan en NULL, al final y en el orden de antes. Se replica a `template_wms` y a cada `emp_*` con `wms_sync_column_to_tenants` (si existe) y la migración la asegura además en cada esquema que tenga la tabla. Esa función no copia CHECK; por eso la migración agrega `chk_orden_venta_linea_posicion_no_negativa` (`posicion IS NULL OR posicion >= 0`) en `public` y en cada esquema. Es idempotente. Prueba en `supabase/tests/124_orden_venta_linea_posicion_test.sql`. **Orden de despliegue:** se aplica primero; la web y la API que leen o escriben `posicion` fallan si la columna no existe. No se aplica sola: la aplica una persona.

- Migración **123**: el rol `authenticated` (Supabase directo) ya no puede cambiar `orden_venta.estado`. Emitir, cancelar y avanzar estado quedan solo en la API Nest (conexión `postgres` / `service_role`). Trigger `trg_orden_venta_emit_cancel_solo_servicio` en `public`, `template_wms` y cada `emp_*`; las demás columnas siguen editables. Es idempotente. Prueba de comportamiento en `supabase/tests/123_ov_estado_solo_api_nest_test.sql` (simula el rol con `SET ROLE` y corre en el humo SQL de CI).

- Migración **122**: columnas `orden_venta_linea.precio_unitario` (`numeric(18,4)` NOT NULL, default 0) y `orden_trabajo.id_orden_venta` (`uuid`), que el API ya usa y ninguna migración creaba (POL-434). Se replican a `template_wms` y a cada `emp_*` con `wms_sync_column_to_tenants`, que no copia FK ni CHECK; por eso la migración agrega el CHECK `chk_orden_venta_linea_precio_no_negativo` (`precio_unitario >= 0`) y la FK `orden_trabajo_id_orden_venta_fkey` (`ON DELETE SET NULL`) en `public` y en cada `emp_*` (la FK no va en `template_wms`). Es idempotente. Si la columna ya existía, no se altera su tipo ni su default: `polaria-wms-dev` la tiene como `numeric` sin precisión, `NOT NULL` y sin default 0, en todos los esquemas. Cambiar eso reescribe la tabla y puede redondear datos, así que queda como decisión aparte. Prueba en `supabase/tests/122_orden_venta_linea_precio_y_ot_id_orden_venta_test.sql`, que corre en el humo SQL de CI y avisa como `DESFASE` esa diferencia sin fallar. Aplicada en `polaria-wms-dev`.

- Migración **121**: activa RLS (sin políticas) y quita todos los permisos de `anon` y `authenticated` sobre `public.mateo_handoff_jti` y `public.rate_limit_bucket`, las tablas de la migración 093 de la API (POL-435). El backend las usa por Prisma. Se guarda con `to_regclass`: si las tablas no existen en la base, no hace nada. Prueba en `supabase/tests/121_mateo_handoff_jti_rate_limit_bucket_rls_test.sql`. No se aplica sola: la aplica una persona después de confirmar el rol de conexión de la API.

- Migración **120**: `comprador_producto_alias` admite varias frases por producto (POL-418). Columna generada `alias_normalizado` con `wms_norm_alias`; se borra el UNIQUE `(id_comprador, id_producto)` en todos los esquemas; índices únicos parciales por frase, por precio (un precio por producto y comprador) y de filas sin frase, más el índice `(codigo_cuenta, id_comprador)`. Se aplica a `public`, `template_wms` y cada `emp_*`. Prueba en `supabase/tests/120_comprador_producto_alias_varias_frases_test.sql`. Script de siembra `scripts/sembrar-comprador-producto-alias.sql` (umbral ≥ 2 líneas y ≥ 80 %, solo categoría venta, termina en `ROLLBACK`).
- Migración **119**: columna `correo_pedido_ingreso.intentos` jsonb (POL-417), arreglo de cada intento de ingreso manual (inicio, fin, duración y resultado). Default `'[]'`, se replica a `template_wms` y a cada `emp_*` con `wms_sync_column_to_tenants`. Es la base del log de tiempos de POL-415. Prueba en `supabase/tests/119_correo_pedido_ingreso_intentos_test.sql`.
- Migración **118**: columna `orden_venta.lineas_materializadas_at` (REQ-280 / REQ-299). Es una reserva atómica para que solo una sesión inserte las líneas que salen de `origen_correo`: la web la toma con un `UPDATE ... WHERE lineas_materializadas_at IS NULL`. Evita que las OV nuevas queden con cada línea duplicada (OV-00001507: 18 productos, 36 líneas). Prueba en `supabase/tests/118_orden_venta_lineas_materializadas_at_test.sql`. Nace en `NULL`, se replica a `template_wms` y a cada `emp_*` con `wms_sync_column_to_tenants`. No corrige las OV ya duplicadas: eso es un SQL aparte que corre una persona.
- Migración **117**: tabla `correo_pedido_entrada` (POL-410), con las columnas de `CorreoFilaDto`, que reemplaza al datatable `correos_aguacates_entrada` de n8n. Llave única (`codigo_cuenta`, `message_id`) para que el `upsert` del flujo no duplique correos, `resultado` y `confianza` con sus valores permitidos (null en filas antiguas) y RLS de lectura por cuenta. Se crea en `public` y se replica a `template_wms` y a cada `emp_*` con `wms_sync_table_to_tenants`. Nace vacía: el histórico y la doble escritura de n8n son pasos aparte.
- Migración **115**: tabla `orden_venta_surtido_captura_intento` (REQ-247), una fila por foto de surtido enviada desde el QR. Es la cola en segundo plano: el api reserva la fila en `recibida` y responde de inmediato; la lectura con IA sigue aparte (`procesando`) hasta `lista` o `fallo`. Guarda la URL de la foto para reintentar sin volver a tomarla, el motivo del fallo y los tiempos por etapa (`tiempos`), así que también deja rastro de las fotos que fallan (REQ-207). Sin llave única por OV y OT: conviven varios intentos. Índice parcial de intentos en curso y RLS de lectura por cuenta. Se crea en `public` y se replica a `template_wms` y a cada `emp_*` con `wms_sync_table_to_tenants`.
- Migración **114**: tabla `correo_pedido_ingreso` (REQ-104) que relaciona el `message_id` de un correo con la OV ingresada a mano desde el WMS. Llave única (`codigo_cuenta`, `message_id`) para no duplicar la OV con varios clics, `estado` (`procesando`, `ingresado`, `error`) para el ingreso asíncrono y RLS de lectura por cuenta. Se crea en `public` y se replica a `template_wms` y a cada `emp_*` con `wms_sync_table_to_tenants`.
- Migración **113**: elimina el UNIQUE viejo solo por `id_orden_venta` en `orden_venta_surtido_captura` (schemas `emp_*` donde la 088 no lo borró por nombre) y asegura `uq_orden_venta_surtido_captura_orden_ot` en `public`, `template_wms` y `emp_*`. Corrige capturas por OT (REQ-193 / REQ-190).
- Migración **112**: agrega `revisada` y `facturada` a `public.estado_orden_venta` (compartido por `template_wms` y todos los `emp_*`). Corrige el error al avanzar OV desde foto QR / Cypher (REQ-058).
- Migración **108**: backfill de `metadatos_catalogo.tipo_producto = 1` en `producto` de todos los schemas (`public`, `template_wms`, `emp_*`) cuando falta; no toca servicios ya marcados con `3`.
- Migración **107**: `bot_materializar_ov_desde_origen` solo asigna comprador con match **exacto** (nombre o código normalizados); elimina fuzzy por token `LIKE` que generaba falsas identificaciones.

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
