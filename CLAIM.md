<!-- polaria-reclamo v1 -->
## 🔒 Reclamo de trabajo en paralelo

**Estado:** ACTIVO
**Issue:** REQ-104
**Rama:** dani/req-104-correos-descartados-ingreso
**Responsable:** Dani
**Confianza:** 60%

### Zonas que voy a tocar
- `migrations/114_correo_pedido_ingreso.sql` — archivo nuevo
- `supabase/migrations/114_correo_pedido_ingreso.sql` — archivo nuevo

### Compartidos (cambio mínimo y aviso)
- `CHANGELOG.md`
- `README.md`

### Por qué
Tabla que relaciona el message_id del correo con la OV ingresada, en todos los schemas de cuenta
