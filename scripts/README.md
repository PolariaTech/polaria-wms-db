# Scripts SQL — Polaria WMS DB

Orden recomendado para validación local o en Supabase SQL Editor.

## 1. Migraciones

| Opción | Archivo |
|--------|---------|
| Supabase (todo en uno) | `all-migrations-supabase.sql` |
| Local / por archivo | `migrations/001` … `018` en `migrations/` |

Antes de validar en local, ejecutar `bootstrap-auth.sql` (schema `auth`, stub `auth.uid()`).

## 2. Seed

```text
validate-phase1.sql
```

Datos base: configurador TI, empresa ACME, cuenta ACME-01, admin y operador.

## 3. Validación RLS (POL-2)

```text
validate-rls-multitenant.sql          # local (bootstrap-auth + app.test_auth_uid)
validate-rls-multitenant-supabase.sql # remoto: npx supabase db query --linked -f ...
```

Extiende el seed (ACME-02, bodegas, custodio, admin empresa) y ejecuta 6 pruebas de aislamiento con `SET LOCAL ROLE authenticated` + `app.test_auth_uid`.

**Requisito:** conectar como rol con permiso para `SET ROLE authenticated` (postgres / owner). No ejecutar las pruebas como superusuario sin `SET ROLE`: RLS se bypassa.

## Supabase SQL Editor

1. Pegar `all-migrations-supabase.sql` (o aplicar migraciones vía CLI).
2. Ejecutar `validate-phase1.sql`.
3. Ejecutar `validate-rls-multitenant.sql`.
4. Revisar mensajes `NOTICE` / ausencia de `ERROR`.

Alternativa manual por usuario JWT: en cada prueba usar  
`SELECT set_config('request.jwt.claim.sub', '<id_auth>', true);`  
y autenticarse en la app; el script documenta UUIDs de prueba.

## Otros

| Archivo | Uso |
|---------|-----|
| `seed-configurador.sql` | Solo usuario TI en entorno vacío |
| `apply-migrations-remote.mjs` | Aplicar migraciones al remoto |
