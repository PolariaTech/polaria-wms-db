<!-- polaria-reclamo v1 -->
## 🔒 Reclamo de trabajo en paralelo

**Estado:** ACTIVO
**Issue:** REQ-193
**Rama:** dani/req-193-indice-captura-por-ot
**Responsable:** Dani
**Confianza:** 90%

### Zonas que voy a tocar
- `migrations/113_orden_venta_surtido_captura_drop_unique_ov.sql`
- `supabase/migrations/113_orden_venta_surtido_captura_drop_unique_ov.sql`
- `CHANGELOG.md`

### Compartidos (cambio mínimo y aviso)
Ninguno.

### Por qué
Quitar UNIQUE viejo por OV para permitir una captura (N fotos) por cada OT
