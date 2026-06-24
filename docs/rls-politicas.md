# Políticas RLS — Polaria WMS (POL-2)

Row Level Security en Supabase para multi-tenant. Migraciones: `015` helpers → `016` lectura por cuenta → `017` bodega → `018` escritura plataforma.

## Modelo de acceso

| Canal | Rol DB | RLS | Uso |
|-------|--------|-----|-----|
| PostgREST / supabase-js (JWT) | `authenticated` | **Aplica** | App web, operadores, configurador TI |
| Backend API (`DATABASE_URL`) | `postgres` | **Bypass** | Inventario, contadores, lógica sensible |
| Anónimo | `anon` | **Aplica** | Sin acceso a tablas de negocio |

El backend conecta como `postgres` y **no** depende de RLS. Debe validar en código: `codigo_empresa`, `codigo_cuenta`, `id_bodega` y permisos del rol operativo.

## Helpers (`015`, `017`)

| Función | Propósito |
|---------|-----------|
| `auth_wms_usuario_actual()` | Contexto del caller activo |
| `auth_wms_es_configurador()` | ¿Es TI / plataforma? |
| `auth_wms_puede_ver_empresa(codigo)` | Alcance SELECT empresa |
| `auth_wms_puede_ver_cuenta(codigo)` | Alcance SELECT cuenta (incluye aislamiento por `codigo_cuenta`) |
| `auth_wms_puede_ver_bodega(uuid)` | Alcance SELECT bodega / asignación |

Todas: `SECURITY DEFINER`, `SET search_path = public`. `GRANT EXECUTE` solo a `authenticated` (uso en políticas, no RPC público a `anon`).

## Matriz rol × operación × tabla

Leyenda: **S** = SELECT acotado, **S+** = SELECT ampliado (admin/config), **C** = INSERT/UPDATE/DELETE configurador, **—** = sin permiso vía PostgREST, **B** = solo backend (`postgres`).

### Catálogo y plataforma

| Tabla | configurador | administrador_cuenta | operador_cuenta | nivel bodega | anon |
|-------|:---:|:---:|:---:|:---:|:---:|
| `rol` | S | S | S | S | — |
| `empresa` | S / **C** | S (su empresa) | S (su empresa) | S (su empresa) | — |
| `cuenta` | S / **C** | S+ (tenant) | S (su cuenta) | S (empresa*) | — |
| `usuario` | S+ / **C** | S+ (tenant) | S (propia fila) | S (propia fila) | — |
| `bodega` | S / **C** | S (cuenta/empresa) | S (su cuenta) | S (asignadas) | — |
| `asignacion_bodega` | S / **C**† | S (bodegas visibles) | S (bodegas visibles) | S (asignadas) | — |

\* Nivel bodega ve cuentas de su empresa hasta refinamiento por bodega en lecturas operativas.  
† Configurador: INSERT + DELETE en asignaciones; sin UPDATE.

### Tablas sensibles futuras (POL-33)

| Tabla (ejemplo) | authenticated | Backend |
|-----------------|---------------|---------|
| `warehouse_state`, contadores, movimientos | **—** (REVOKE explícito) | **B** |

Patrón en migración:

```sql
REVOKE INSERT, UPDATE, DELETE ON warehouse_state FROM authenticated;
-- GRANT SELECT solo con política SELECT explícita
```

## Políticas de escritura (`018`)

Solo **`auth_wms_es_configurador()`** puede escribir vía PostgREST en tablas de plataforma:

| Tabla | INSERT | UPDATE | DELETE |
|-------|:------:|:------:|:------:|
| `empresa` | ✓ | ✓ | — |
| `cuenta` | ✓ | ✓ | — |
| `usuario` | ✓ | ✓ | — |
| `bodega` | ✓ | ✓ | — |
| `asignacion_bodega` | ✓ | — | ✓ |

- **INSERT**: `WITH CHECK (auth_wms_es_configurador())`
- **UPDATE**: `USING` + `WITH CHECK` con el mismo predicado (fila visible vía SELECT previo)
- **DELETE** (`asignacion_bodega`): `USING (auth_wms_es_configurador())`

Clientes (`administrador_cuenta`, operadores, bodega) **no** tienen INSERT/UPDATE/DELETE en ninguna tabla expuesta.

## Convención tenant (tablas operativas)

Toda tabla operativa futura debe incluir:

- `codigo_cuenta` → FK `cuenta`
- `id_bodega` → FK `bodega`

`codigo_empresa` se obtiene vía join; no duplicar en hijos de `bodega`.

## Referencias

- [Login fase 1](login-fase1.md) — esquema auth y contexto de sesión
- [ADR-001 Multi-tenant](adr/ADR-001-multi-tenant.md)
- [ADR-003 RBAC](adr/ADR-003-rbac.md)
