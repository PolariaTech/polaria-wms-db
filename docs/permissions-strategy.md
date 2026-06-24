# Estrategia de permisos y contrato de escritura

Modelo de permisos de la base de datos: **lectura filtrada por RLS para el cliente,
escritura exclusiva por backend**.

## Roles de base de datos (Supabase)

| Rol             | Uso                                | Sujeto a RLS |
|-----------------|------------------------------------|--------------|
| `anon`          | Cliente sin sesión                 | sí           |
| `authenticated` | Cliente con sesión (JWT Supabase)  | sí           |
| `service_role`  | Backend privilegiado               | no (bypass)  |
| `postgres`      | Conexión directa del backend (Prisma) | no (owner) |

## Privilegios sobre tablas fundacionales (`rol`, `empresa`, `usuario`, `cuenta`)

- `anon`: **sin privilegios**.
- `authenticated`: **solo `SELECT`** (filtrado por RLS).
- Escrituras (`INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`): **no** concedidas a
  `anon`/`authenticated`. Se ejecutan por backend.

> Supabase concede por defecto `ALL` (incluido `TRUNCATE`, que NO respeta RLS) a
> `anon`/`authenticated`. La migración `015_rls_base.sql` revoca ese default y
> reconcede solo `SELECT` a `authenticated`.

## Contrato de escritura ("escrituras sensibles vía backend")

Las mutaciones sensibles —inventario, contadores, `warehouse_state`, órdenes,
onboarding de empresa/tenant/bodega— se realizan **siempre** desde
`polaria-wms-api`:

- Conexión directa Postgres (`DATABASE_URL=postgresql://postgres:...`) o
  `service_role`, ambos exentos de RLS.
- El backend aplica las reglas de negocio y de autorización por rol (RBAC) antes
  de mutar. La BD garantiza que nadie escriba "por fuera" del backend.

## Reglas especiales

- **Configurador**: opera sin `codigo_cuenta`; tiene visibilidad de plataforma en
  lectura. Sus operaciones de alta (empresas, cuentas, usuarios) van por backend.
- **Catálogo `rol`**: `SELECT` abierto a cualquier `authenticated` (no es dato de
  tenant).

## RBAC en aplicación

El control fino por rol/acción (qué puede hacer cada rol en cada módulo) se
implementa en la capa de aplicación (`polaria-wms-api`). La BD provee el
aislamiento por tenant (RLS) y el contrato de mínimo privilegio. Ver
[ADR-003 — RBAC](adr/ADR-003-rbac.md).
