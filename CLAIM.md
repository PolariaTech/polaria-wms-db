<!-- polaria-reclamo v1 -->
## 🔒 Reclamo de trabajo en paralelo

**Estado:** ACTIVO
**Issue:** REQ-439
**Rama:** lucho/req-439-evitar-ov-duplicadas-y-ot-perdidas
**Responsable:** Lucho
**Confianza:** 50%

### Zonas que voy a tocar
- `supabase/migrations/119_correo_pedido_ingreso_intentos.sql`
- `migrations/119_correo_pedido_ingreso_intentos.sql`
- `supabase/tests/119_correo_pedido_ingreso_intentos_test.sql`

### Compartidos (cambio mínimo y aviso)
Ninguno.

### Por qué
POL-453 (REQ-439): señal de vida del ingreso en correo_pedido_ingreso, columna nueva con migración 125 (archivo nuevo) que amplía la tabla de la migración 119; los archivos de 119 son la zona conocida, la migración nueva no se reclama.
