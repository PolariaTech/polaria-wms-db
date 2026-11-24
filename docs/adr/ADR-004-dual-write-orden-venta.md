# ADR-004 — Dual-write / canales híbridos de Orden de Venta

- **Estado:** Aceptado
- **Fecha:** 2026-11-23
- **Repos:** polaria-wms-web, polaria-wms-api, polaria-wms-db
- **Relacionados:** migraciones `121_ov_estado_emit_cancel_solo_servicio`, `122_ov_avance_estado_restriccion`; `docs/ARQUITECTURA-COMUNICACION.md` (web); `src/lib/architecture/wms-channels.ts`

## Contexto

El WMS opera un **híbrido intencional** A (Supabase+RLS) + B (Nest) + D (BFF Next). Las mutaciones de **estado** de `orden_venta` son el punto más sensible: triggers 121/122 bloquean que el rol `authenticated` cambie `estado` fuera de Nest.

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

- Cypher y surtido QR no pueden mutar `estado` con JWT `authenticated` (122).
- El BFF de captura requiere `INTERNAL_API_KEY` alineada con Nest.
- Listados de procesamiento exigen cuenta+bodega (Nest); no hay fallback silencioso a Supabase.
- Tests de invariante: `wms-channels.test.ts` + specs de `avanzarEstado` / surtido.

## Fases

| Fase | Qué | Estado |
|------|-----|--------|
| F0 | Emitir/cancelar Nest + triggers 121 | Hecho |
| F1 | Avance Cypher Nest + 122 | Hecho |
| F2 | Surtido QR → Nest (`avanzar-estado-surtido`) | Hecho (Score-10 P0) |
| F3 | (Opcional) migrar más mutaciones de borrador a Nest | Futuro, con ticket |
