# ADR-004 — Dual-write / canales híbridos de Orden de Venta

- **Estado:** Aceptado
- **Fecha:** 2026-11-23
- **Repos:** polaria-wms-web, polaria-wms-api, polaria-wms-db
- **Relacionados:** migraciones `080_orden_venta_update_editable_operador` y `094_estado_orden_venta_por_confirmar` (política RLS `orden_venta_update_editable`); `docs/ARQUITECTURA-COMUNICACION.md` (web); `src/lib/architecture/wms-channels.ts`

## Contexto

El WMS opera un **híbrido intencional** A (Supabase+RLS) + B (Nest) + D (BFF Next). Las mutaciones de **estado** de `orden_venta` son el punto más sensible. Hoy la base **no** tiene un trigger que impida al rol `authenticated` cambiar `estado`: la política `orden_venta_update_editable` (080, redefinida en 094) permite `UPDATE` a `administrador_cuenta` y `operador_cuenta` mientras la OV está en un estado editable. La regla «solo Nest escribe el estado» se cumple por contrato en el código (`OV_CHANNEL_CONTRACT`), no por la base de datos; endurecerla es la fase F4.

Hacía falta un ADR que fije qué queda en A, qué es B obligatorio, y cómo el surtido QR deja de ser un segundo writer vía `service_role`.

## Decisión

1. **Canal A (Supabase):** listado, detalle y borrador OV (`por_confirmar`); lecturas RLS; materializar/locks livianos ya existentes.
2. **Canal B (Nest) — único writer de estado post-borrador:**
   - `POST …/emitir`, `POST …/cancelar`
   - `POST …/avanzar-estado` (Cypher / JWT)
   - `POST …/avanzar-estado-surtido` (captura QR / `INTERNAL_API_KEY`)
3. **Canal D (BFF):** captura de fotos, Storage, OpenAI; **calcula** el hito de alistamiento y **delega la escritura de estado a Nest** (no `UPDATE orden_venta.estado` con admin).
4. Contrato ejecutable: `OV_CHANNEL_CONTRACT` en web. Cualquier cambio de canal exige ticket + tests.

## Consecuencias

- Por contrato, Cypher y surtido QR no mutan `estado` con JWT `authenticated`. La base todavía no lo impide (ver F4).
- El BFF de captura requiere `INTERNAL_API_KEY` alineada con Nest.
- Listados de procesamiento exigen cuenta+bodega (Nest); no hay fallback silencioso a Supabase.
- Tests de invariante: `wms-channels.test.ts` + specs de `avanzarEstado` / surtido.

## Fases

| Fase | Qué | Estado |
|------|-----|--------|
| F0 | Emitir/cancelar en Nest | Hecho (API) |
| F1 | Avance Cypher en Nest | Hecho (API) |
| F2 | Surtido QR → Nest (`avanzar-estado-surtido`) | Hecho (Score-10 P0) |
| F3 | (Opcional) migrar más mutaciones de borrador a Nest | Futuro, con ticket |
| F4 | Restricción en la base: que `authenticated` no pueda cambiar `estado` (trigger o permiso por columna) | Pendiente, con ticket |
