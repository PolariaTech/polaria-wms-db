# Scripts SQL — Polaria WMS DB

Orden recomendado para validación local o en Supabase SQL Editor.

## 1. Migraciones

| Opción | Archivo / ruta |
|--------|----------------|
| Supabase (todo en uno) | `all-migrations-supabase.sql` |
| Supabase CLI | `supabase db push` (`migrations/` ↔ `supabase/migrations/`) |
| Local / por archivo | `migrations/001` … `040` |

Antes de validar en local, ejecutar `bootstrap-auth.sql` (schema `auth`, stub `auth.uid()`).

## 2. Seed

```text
validate-phase1.sql
```

Datos base: configurador TI, empresa ACME, cuenta ACME-01, admin y operador.

## 3. Validación RLS

```text
validate-rls-multitenant.sql          # POL-2 (001–019)
validate-rls-multitenant-supabase.sql # remoto: npx supabase db query --linked -f ...
validate-rls-operativo.sql            # POL-33 (020–030), tras multitenant
validate-rls-pol138.sql               # POL-138 (7 tablas críticas + cross-tenant)
validate-widget-auth-pol137.sql       # POL-137 (historial widget_conversacion + spoof cuenta)
```

`validate-rls-multitenant.sql` extiende el seed (ACME-02, bodegas, custodio, admin empresa) y ejecuta 6 pruebas POL-2.

`validate-rls-operativo.sql` añade seed operativo mínimo (productos, layout, warehouse_state) y prueba:

- Operador no ve productos de otra cuenta
- Operador no puede INSERT en `warehouse_state`
- Configurador ve catálogos multi-cuenta
- Custodio ve stock solo de su bodega asignada

Simulación: `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claim.sub', '<id_auth>', true)`.

**Requisito:** conectar como postgres (o rol con permiso para `SET ROLE authenticated`).

## Supabase SQL Editor

1. Pegar `all-migrations-supabase.sql` (o `supabase db push`).
2. Ejecutar `validate-phase1.sql`.
3. Ejecutar `validate-rls-multitenant.sql`.
4. Ejecutar `validate-rls-operativo.sql`.
5. Ejecutar `validate-rls-pol138.sql` (POL-138).
6. Revisar mensajes `NOTICE` / ausencia de `ERROR`.

## Otros

| Archivo | Uso |
|---------|-----|
| `seed-configurador.sql` | Solo usuario TI en entorno vacío |
| `apply-migrations-remote.mjs` | Aplicar migraciones al remoto |
| `apply-remote-migrations.ps1` | Wrapper PowerShell migraciones |
| `verify-schema-v1-alignment.sql` | Comprueba tablas/columnas 031–040 en remoto |
