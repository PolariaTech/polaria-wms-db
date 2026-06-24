# Row Level Security (RLS) — capa base multi-tenant

Esta carpeta documenta la estrategia de RLS de `polaria-wms-db`. La implementación
vive en las migraciones SQL (`migrations/`), no en archivos sueltos aquí.

- Migración base: [`migrations/015_rls_base.sql`](../migrations/015_rls_base.sql)
- Validación: [`scripts/validate-rls.sql`](../scripts/validate-rls.sql)

## Modelo de aislamiento

| Nivel       | Clave de aislamiento | Roles                                                   |
|-------------|----------------------|---------------------------------------------------------|
| Plataforma  | (sin tenant)         | `configurador` (TI). Ve y opera todo.                   |
| Empresa     | `codigo_empresa`     | `administrador_cuenta`, `operador_cuenta`.              |
| Cuenta/Tenant | `codigo_cuenta`    | usuarios de cuenta y bodega del tenant.                 |
| Bodega      | `id_bodega`          | roles de bodega (se añade al expandir el modelo).       |

- El **configurador** no tiene `codigo_empresa` ni `codigo_cuenta` (ver
  `chk_usuario_contexto` en `012_user.sql`) y obtiene acceso de plataforma.
- Los **demás usuarios** solo ven datos de su tenant (`codigo_cuenta`) o, cuando
  aún no tienen cuenta asignada, de su empresa (`codigo_empresa`).

## Helpers de contexto (`app` schema)

Las políticas no repiten subconsultas: usan funciones `SECURITY DEFINER` y `STABLE`
que resuelven el contexto del usuario autenticado (`auth.uid()`). Viven en el
esquema `app`, que **no** se expone vía PostgREST (ver `supabase/config.toml`),
por lo que no aparecen como RPC públicas.

| Función                                  | Devuelve                               |
|------------------------------------------|----------------------------------------|
| `app.current_rol()`                      | `wms_rol` del usuario actual            |
| `app.is_configurador()`                  | `boolean`                               |
| `app.current_codigo_empresa()`           | `varchar` (NULL si configurador)        |
| `app.current_codigo_cuenta()`            | `varchar` (NULL si configurador/sin cuenta) |
| `app.has_empresa_access(codigo_empresa)` | `boolean` (configurador O misma empresa)|
| `app.has_cuenta_access(codigo_cuenta)`   | `boolean` (configurador O mismo tenant) |

> Son `SECURITY DEFINER` (propietario `postgres`) para leer `usuario` sin disparar
> RLS recursiva sobre la propia tabla. Solo devuelven el contexto del llamante, por
> lo que no filtran datos de terceros.

## Contrato de escritura (seguridad por diseño)

- El rol `authenticated` solo tiene **SELECT** (filtrado por RLS) sobre
  `rol`, `empresa`, `usuario`, `cuenta`.
- El rol `anon` **no tiene ningún privilegio** sobre estas tablas.
- **Todas las escrituras** (inventario, contadores, órdenes, onboarding) se
  ejecutan desde `polaria-wms-api` con la conexión directa `postgres`
  (`DATABASE_URL`) o con `service_role`, ambos **exentos de RLS**.
- Se revoca explícitamente `TRUNCATE`/DML del default de Supabase para `anon` y
  `authenticated` (RLS no controla `TRUNCATE`).

## Plantilla para tablas operativas futuras (POL-33 / POL-40)

Al crear una tabla operativa, habilitar RLS y aplicar el patrón según su clave:

```sql
-- Tabla con tenant (codigo_cuenta)
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;

CREATE POLICY <tabla>_select_tenant
    ON <tabla>
    FOR SELECT
    TO authenticated
    USING (app.has_cuenta_access(<tabla>.codigo_cuenta));

-- Solo SELECT a authenticated; las escrituras van por backend.
REVOKE ALL ON <tabla> FROM anon, authenticated;
GRANT SELECT ON <tabla> TO authenticated;
```

Para tablas con `codigo_empresa` usar `app.has_empresa_access(...)`.

### Aislamiento adicional por bodega (`id_bodega`)

Cuando exista la tabla `bodega` y la membresía usuario↔bodega, añadir un helper
análogo (p. ej. `app.has_bodega_access(id_bodega)`) que combine
`app.is_configurador()`, el tenant del usuario y su asignación de bodega, y
componer la política:

```sql
USING (
    app.has_cuenta_access(<tabla>.codigo_cuenta)
    AND app.has_bodega_access(<tabla>.id_bodega)
)
```

## Validación

```bash
# Como postgres / service_role (SQL Editor de Supabase o psql)
\i scripts/validate-rls.sql
```

Comprueba RLS habilitado, políticas activas, helpers presentes y simula la
visibilidad por tenant.
