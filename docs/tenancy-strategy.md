# Estrategia multi-tenant

Polaria App v2.0 es una plataforma SaaS multi-tenant. El aislamiento se modela en
tres niveles jerárquicos sobre una única base de datos Postgres (Supabase), con
Row Level Security (RLS) como mecanismo de aislamiento por diseño.

## Jerarquía

```
empresa (codigo_empresa)
  └── cuenta / tenant (codigo_cuenta)
        └── bodega (id_bodega)   [se añade en POL-33 / POL-40]
```

- **empresa**: persona jurídica cliente del SaaS.
- **cuenta**: tenant operativo dentro de una empresa (`codigo_cuenta`). Es la
  unidad principal de aislamiento de la operación.
- **bodega**: ubicación física dentro de un tenant (modelo operativo futuro).

## Roles y alcance

Definidos en `migrations/002_enums.sql` (`wms_rol`) y `010_roles.sql`:

| Rol                    | Nivel       | Tenant |
|------------------------|-------------|--------|
| `configurador`         | plataforma  | —      |
| `administrador_cuenta` | cuenta      | sí     |
| `operador_cuenta`      | cuenta      | sí     |
| `administrador_bodega` | bodega      | sí     |
| `jefe_bodega`          | bodega      | sí     |
| `custodio`             | bodega      | sí     |
| `operario`             | bodega      | sí     |
| `procesador`           | bodega      | sí     |
| `transportista`        | bodega      | sí     |

El `configurador` (equipo TI del proveedor) no pertenece a ninguna empresa ni
cuenta (`chk_usuario_contexto`), y por tanto puede operar sin `codigo_cuenta` y
ver/gestionar todos los tenants.

## Aislamiento

- **Lectura**: gobernada por RLS. Cada usuario autenticado solo ve filas de su
  tenant (`codigo_cuenta`) o empresa (`codigo_empresa`); el configurador ve todo.
  Ver [`rls/README.md`](../rls/README.md).
- **Escritura**: centralizada en `polaria-wms-api` (NestJS), que usa la conexión
  directa `postgres` / `service_role` (exenta de RLS). El frontend nunca escribe
  directamente sobre las tablas con la `anon`/`authenticated` key.

## Identidad

`auth.users` (Supabase Auth) ↔ `public.usuario` por `id_auth`. El JWT emitido por
Supabase Auth provee `auth.uid()`, base de todos los helpers de contexto del
esquema `app`.

## Decisiones relacionadas

- [ADR-001 — Multi-tenant](adr/ADR-001-multi-tenant.md)
- [ADR-002 — Auth en Supabase](adr/ADR-002-auth-supabase.md)
- [ADR-003 — RBAC](adr/ADR-003-rbac.md)
