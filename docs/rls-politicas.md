# Políticas RLS — Polaria WMS (POL-2 + POL-33)

Row Level Security en Supabase para multi-tenant. Migraciones POL-2: `015` helpers → `016` lectura por cuenta → `017` bodega → `018` escritura plataforma. POL-33 operativo: `020`–`029` por dominio → `030` helper consolidado.

## Modelo de acceso

| Canal | Rol DB | RLS | Uso |
|-------|--------|-----|-----|
| PostgREST / supabase-js (JWT) | `authenticated` | **Aplica** | App web, operadores, configurador TI |
| Backend API (`DATABASE_URL`) | `postgres` | **Bypass** | Inventario, contadores, lógica sensible |
| Anónimo | `anon` | **Aplica** | Sin acceso a tablas de negocio |

El backend conecta como `postgres` y **no** depende de RLS. Debe validar en código: `codigo_empresa`, `codigo_cuenta`, `id_bodega` y permisos del rol operativo.

## Helpers (`015`, `017`, `021`, `030`)

| Función | Propósito |
|---------|-----------|
| `auth_wms_usuario_actual()` | Contexto del caller activo |
| `auth_wms_es_configurador()` | ¿Es TI / plataforma? |
| `auth_wms_puede_ver_empresa(codigo)` | Alcance SELECT empresa |
| `auth_wms_puede_ver_cuenta(codigo)` | Alcance SELECT cuenta |
| `auth_wms_puede_ver_bodega(uuid)` | Alcance SELECT bodega / asignación |
| `auth_wms_puede_gestionar_catalogo_cuenta(codigo)` | INSERT/UPDATE catálogos (configurador o admin cuenta) |
| `auth_wms_puede_ver_fila_operativa(cuenta, bodega)` | SELECT C+B estándar; `bodega` NULL = solo cuenta |

Todas: `SECURITY DEFINER`, `SET search_path = public`. `GRANT EXECUTE` a `authenticated` (uso en políticas).

Predicado estándar **C+B**:

```sql
auth_wms_puede_ver_cuenta(codigo_cuenta)
AND auth_wms_puede_ver_bodega(id_bodega)
-- equivalente: auth_wms_puede_ver_fila_operativa(codigo_cuenta, id_bodega)
```

## Matriz rol × operación × tabla

Leyenda: **S** = SELECT acotado, **S+** = SELECT ampliado, **W** = escritura catálogo (admin/config), **C** = INSERT/UPDATE/DELETE configurador plataforma, **—** = sin permiso PostgREST, **B** = solo backend.

### Catálogo y plataforma (POL-2)

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

### Operativo POL-33 — Layout (`020`)

| Tabla | SELECT | INSERT/UPDATE/DELETE PostgREST |
|-------|--------|------------------------------|
| `tipo_ubicacion`, `zona`, `ubicacion` | S (cuenta + bodega) | **—** (backend) |

### Operativo POL-33 — Catálogos (`021`)

| Tabla | SELECT | INSERT/UPDATE | DELETE |
|-------|--------|---------------|--------|
| `proveedor`, `cliente`, `producto`, `comprador`, `planta`, `camion` | S (cuenta) | **W** (config / admin cuenta) | solo configurador |

### Operativo POL-33 — Compras (`022`)

| Tabla | SELECT | Escritura PostgREST |
|-------|--------|---------------------|
| `solicitud_compra`, `solicitud_compra_linea` | S (cuenta + bodega) | **—** (backend) |
| `orden_compra`, `orden_compra_linea` | S (cuenta + bodega) | **—** (backend) |

### Operativo POL-33 — Inventario (`023`, `024`)

| Tabla | SELECT | Escritura PostgREST |
|-------|--------|---------------------|
| `lote` | S (bodega) | **B** |
| `warehouse_state` | S (bodega) | **B** |
| `movimiento_inventario` | S (bodega) | **B** (append-only) |

### Operativo POL-33 — Procesamiento y ventas (`027`, `028`)

| Tabla | SELECT | Escritura PostgREST |
|-------|--------|---------------------|
| `orden_trabajo`, `orden_trabajo_linea` | S (cuenta + bodega) | **—** (backend) |
| `orden_venta`, `orden_venta_linea` | S (cuenta + bodega) | **—** (backend) |

### Operativo POL-33 — Transporte (`029`)

| Tabla | SELECT | Escritura PostgREST |
|-------|--------|---------------------|
| `viaje_transporte`, `guia_envio`, `evidencia_transporte` | S (cuenta + bodega vía viaje) | **—** (backend) |

### Operativo POL-33 — Contadores y auditoría (`025`, `026`)

| Tabla | SELECT | Escritura PostgREST |
|-------|--------|---------------------|
| `contador` | **—** | **B** |
| `auditoria_operacion` | S (admin cuenta / configurador) | **B** (append-only) |

Patrón tablas sensibles:

```sql
REVOKE INSERT, UPDATE, DELETE ON warehouse_state FROM authenticated;
GRANT SELECT ON warehouse_state TO authenticated;
-- política SELECT con auth_wms_puede_ver_bodega(id_bodega)
```

## Políticas de escritura plataforma (`018`)

Solo **`auth_wms_es_configurador()`** puede escribir vía PostgREST en tablas POL-2:

| Tabla | INSERT | UPDATE | DELETE |
|-------|:------:|:------:|:------:|
| `empresa` | ✓ | ✓ | — |
| `cuenta` | ✓ | ✓ | — |
| `usuario` | ✓ | ✓ | — |
| `bodega` | ✓ | ✓ | — |
| `asignacion_bodega` | ✓ | — | ✓ |

## Convención tenant (tablas operativas)

- `codigo_cuenta` → FK `cuenta` (siempre en operativas)
- `id_bodega` → FK `bodega` (cuando aplica alcance físico)
- `codigo_empresa` vía join; no duplicar en hijos de bodega

## Validación

| Script | Alcance |
|--------|---------|
| `validate-rls-multitenant.sql` | POL-2: cuenta, bodega, plataforma |
| `validate-rls-operativo.sql` | POL-33: catálogos, warehouse_state, helper `030` |

## Referencias

- [Modelo operativo V2](modelo-operativo-v2.md)
- [Login fase 1](login-fase1.md)
- [ADR-001 Multi-tenant](adr/ADR-001-multi-tenant.md)
- [ADR-003 RBAC](adr/ADR-003-rbac.md)

## Excluido (sin RLS POL-33)

Tablas Mateo: `mateo_conversacion`, `mateo_historial`, `document_chunks`, `users`, `requirements` — issues aparte.
