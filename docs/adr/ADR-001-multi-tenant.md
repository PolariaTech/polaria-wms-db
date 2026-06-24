# ADR-001 — Arquitectura multi-tenant

- Estado: Aceptado
- Contexto: Polaria App v2.0 (SaaS) — POL-2

## Contexto

La plataforma debe alojar múltiples empresas/cuentas en una misma base de datos
manteniendo aislamiento estricto entre tenants y evitando accesos cruzados.

## Decisión

Adoptar **multi-tenancy por base de datos compartida con discriminador de tenant**
y **Row Level Security (RLS)** como mecanismo de aislamiento por diseño.

- Discriminadores: `codigo_empresa` (empresa) y `codigo_cuenta` (tenant); a futuro
  `id_bodega` para el nivel bodega.
- Identidad vía Supabase Auth (`auth.users`) enlazada a `public.usuario` por
  `id_auth`; `auth.uid()` alimenta los helpers de contexto del esquema `app`.
- **Lectura** filtrada por RLS para `authenticated`; `anon` sin acceso a tablas de
  negocio.
- **Escritura** exclusiva por backend (`postgres`/`service_role`, exentos de RLS),
  que aplica RBAC y reglas de negocio.
- El `configurador` (TI) es un rol de plataforma sin tenant, con visibilidad
  global en lectura.

## Alternativas consideradas

- **Una base de datos por tenant**: mayor aislamiento físico, pero costo
  operativo y de aprovisionamiento alto; descartado para el MVP.
- **Esquema por tenant**: complejidad de migraciones multiplicada por tenant;
  descartado.
- **Filtrado solo en la aplicación (sin RLS)**: frágil ante errores de código;
  descartado por no ser "seguro por diseño".

## Consecuencias

- (+) Aislamiento garantizado a nivel de BD, independiente de bugs de aplicación.
- (+) Onboarding de tenants sin aprovisionar infraestructura nueva.
- (+) Helpers reutilizables (`app.*`) para extender RLS a tablas operativas.
- (−) Las políticas RLS deben mantenerse en cada tabla operativa nueva (mitigado
  con la plantilla en `rls/README.md`).
- (−) El backend concentra la responsabilidad de las escrituras y su autorización.

## Implementación

- `migrations/015_rls_base.sql` (helpers `app.*`, políticas, mínimo privilegio).
- Validación: `scripts/validate-rls.sql`.
- Detalle: [`rls/README.md`](../../rls/README.md),
  [`docs/tenancy-strategy.md`](../tenancy-strategy.md),
  [`docs/permissions-strategy.md`](../permissions-strategy.md).
