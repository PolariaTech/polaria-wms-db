# Modelo operativo V2 — POL-33

Diseño de esquema para el WMS operativo. Extiende POL-2 (migraciones `001`–`019`) sin modificar tablas existentes ni tablas Mateo (`mateo_conversacion`, `mateo_historial`, `document_chunks`, `users`, `requirements`).

**Alcance de esta fase:** solo documentación. Las migraciones SQL se implementarán en fases posteriores (`020`–`030`).

## Convenciones tenant (heredadas de `017_bodega_base.sql`)

| Regla | Detalle |
|-------|---------|
| Aislamiento comercial | Toda tabla operativa incluye `codigo_cuenta varchar(32) NOT NULL` → FK `cuenta` |
| Aislamiento físico | Tablas ligadas a una bodega incluyen `id_bodega uuid NOT NULL` → FK `bodega` |
| Empresa | `codigo_empresa` se resuelve vía `cuenta`; **no** duplicar en hijos de `bodega` |
| Escritura sensible | `warehouse_state`, `movimiento_inventario`, `contador`: mutaciones solo backend (`REVOKE` a `authenticated`) |
| Timestamps | `created_at`, `updated_at` con trigger `set_updated_at()` donde aplique |

### Tablas existentes (POL-2) — referencia

```
cuenta ──► bodega ──► asignacion_bodega ◄── usuario
   ▲                        │
   └── empresa ◄────────────┘ (vía join, no FK directa en hijos)
```

---

## 1. Diagrama ER por dominio

Leyenda de alcance:

- **C** = solo `codigo_cuenta`
- **C+B** = `codigo_cuenta` + `id_bodega`

```mermaid
erDiagram
    cuenta ||--o{ bodega : tiene
    bodega ||--o{ zona : contiene
    bodega ||--o{ tipo_ubicacion : define
    zona ||--o{ ubicacion : agrupa
    tipo_ubicacion ||--o{ ubicacion : clasifica

    cuenta ||--o{ proveedor : C
    cuenta ||--o{ cliente : C
    cuenta ||--o{ producto : C
    cuenta ||--o{ comprador : C
    cuenta ||--o{ planta : C
    cuenta ||--o{ camion : C

    bodega ||--o{ solicitud_compra : C+B
    solicitud_compra ||--|{ linea_solicitud_compra : tiene
    producto ||--o{ linea_solicitud_compra : referencia

    proveedor ||--o{ orden_compra : C+B
    bodega ||--o{ orden_compra : recibe
    orden_compra ||--|{ linea_orden_compra : tiene
    producto ||--o{ linea_orden_compra : referencia
    solicitud_compra ||--o| orden_compra : origina

    bodega ||--o{ lote : C+B
    producto ||--o{ lote : traza
    ubicacion ||--o{ warehouse_state : almacena
    producto ||--o{ warehouse_state : stock
    lote ||--o{ warehouse_state : opcional
    bodega ||--o{ movimiento_inventario : C+B
    movimiento_inventario }o--|| ubicacion : origen_destino
    movimiento_inventario }o--|| producto : afecta
    movimiento_inventario }o--o| lote : traza

    bodega ||--o{ orden_trabajo : C+B
    orden_trabajo ||--|{ linea_orden_trabajo : tiene
    producto ||--o{ linea_orden_trabajo : entrada_salida

    cliente ||--o{ orden_venta : C+B
    bodega ||--o{ orden_venta : despacha
    orden_venta ||--|{ linea_orden_venta : tiene
    producto ||--o{ linea_orden_venta : referencia

    camion ||--o{ viaje_transporte : C
    bodega ||--o{ viaje_transporte : origen
    viaje_transporte ||--o{ guia_envio : agrupa
    orden_venta ||--o{ guia_envio : despacha

    bodega ||--o{ auditoria_operacion : C+B
    bodega ||--o{ contador : C+B_opcional

    cuenta {
        varchar codigo_cuenta PK
    }
    bodega {
        uuid id_bodega PK
        varchar codigo_cuenta FK
    }
    tipo_ubicacion {
        uuid id_tipo_ubicacion PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        varchar codigo
        varchar nombre
    }
    zona {
        uuid id_zona PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        varchar codigo
    }
    ubicacion {
        uuid id_ubicacion PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        uuid id_zona FK
        uuid id_tipo_ubicacion FK
        varchar codigo
    }
    proveedor {
        uuid id_proveedor PK
        varchar codigo_cuenta FK
        varchar codigo
        varchar razon_social
    }
    cliente {
        uuid id_cliente PK
        varchar codigo_cuenta FK
        varchar codigo
        varchar razon_social
    }
    producto {
        uuid id_producto PK
        varchar codigo_cuenta FK
        varchar sku
        varchar nombre
        varchar unidad_medida
    }
    comprador {
        uuid id_comprador PK
        varchar codigo_cuenta FK
        varchar codigo
        varchar nombre
    }
    planta {
        uuid id_planta PK
        varchar codigo_cuenta FK
        varchar codigo
        varchar nombre
    }
    camion {
        uuid id_camion PK
        varchar codigo_cuenta FK
        varchar placa
        varchar descripcion
    }
    solicitud_compra {
        uuid id_solicitud_compra PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        varchar numero
        estado_sol estado
    }
    linea_solicitud_compra {
        uuid id_linea PK
        uuid id_solicitud_compra FK
        uuid id_producto FK
        numeric cantidad_solicitada
    }
    orden_compra {
        uuid id_orden_compra PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        uuid id_proveedor FK
        uuid id_solicitud_compra FK
        varchar numero
        estado_oc estado
    }
    linea_orden_compra {
        uuid id_linea PK
        uuid id_orden_compra FK
        uuid id_producto FK
        numeric cantidad_ordenada
        numeric cantidad_recibida
    }
    lote {
        uuid id_lote PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        uuid id_producto FK
        varchar codigo_lote
        estado_lote estado
        date fecha_vencimiento
    }
    warehouse_state {
        uuid id_warehouse_state PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        uuid id_ubicacion FK
        uuid id_producto FK
        uuid id_lote FK
        numeric cantidad
        numeric cantidad_reservada
    }
    movimiento_inventario {
        uuid id_movimiento PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        tipo_movimiento tipo
        uuid id_producto FK
        uuid id_ubicacion_origen FK
        uuid id_ubicacion_destino FK
        uuid id_lote FK
        numeric cantidad
        varchar referencia_tipo
        uuid referencia_id
    }
    orden_trabajo {
        uuid id_orden_trabajo PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        varchar numero
        estado_ot estado
    }
    linea_orden_trabajo {
        uuid id_linea PK
        uuid id_orden_trabajo FK
        uuid id_producto FK
        tipo_linea_ot tipo_linea
        numeric cantidad
    }
    orden_venta {
        uuid id_orden_venta PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        uuid id_cliente FK
        varchar numero
        estado_ov estado
    }
    linea_orden_venta {
        uuid id_linea PK
        uuid id_orden_venta FK
        uuid id_producto FK
        numeric cantidad_pedida
        numeric cantidad_despachada
    }
    viaje_transporte {
        uuid id_viaje PK
        varchar codigo_cuenta FK
        uuid id_bodega_origen FK
        uuid id_camion FK
        varchar numero
        estado_viaje estado
    }
    guia_envio {
        uuid id_guia PK
        varchar codigo_cuenta FK
        uuid id_viaje FK
        uuid id_orden_venta FK
        varchar numero
        estado_guia estado
    }
    auditoria_operacion {
        uuid id_auditoria PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        tipo_auditoria tipo
        varchar entidad
        uuid entidad_id
        jsonb payload
    }
    contador {
        uuid id_contador PK
        varchar codigo_cuenta FK
        uuid id_bodega FK
        nombre_contador nombre
        bigint valor_actual
    }
```

### Notas de diseño por dominio

| Dominio | Alcance tenant | Observaciones |
|---------|----------------|---------------|
| Layout | C+B | `tipo_ubicacion`, `zona`, `ubicacion` son propios de cada bodega |
| Catálogos | C | Maestros compartidos entre bodegas de la misma cuenta |
| Compras / Ventas / OT | C+B | Documentos operativos anclados a bodega de recepción, despacho o procesamiento |
| Inventario | C+B | `warehouse_state` es la foto de stock; mutaciones vía `movimiento_inventario` (backend) |
| Transporte | C (+ bodega origen) | `camion` es cuenta; `viaje_transporte` sale de una bodega; `guia_envio` enlaza OV |
| Auditoría | C+B | `id_bodega` nullable para eventos a nivel cuenta |
| Contadores | C (+ B opcional) | Secuencias por cuenta o por bodega (`id_bodega` NULL = ámbito cuenta) |

---

## 2. Enums nuevos

Migración planificada: `020_operative_enums.sql`. No modifica `wms_rol` ni `rol_nivel` (`002_enums.sql`).

| Enum | Valores | Uso |
|------|---------|-----|
| `estado_sol` | `borrador`, `pendiente_aprobacion`, `aprobada`, `rechazada`, `convertida`, `cancelada` | Cabecera `solicitud_compra` |
| `estado_oc` | `borrador`, `emitida`, `parcialmente_recibida`, `recibida`, `cerrada`, `cancelada` | Cabecera `orden_compra` |
| `estado_ot` | `planificada`, `en_proceso`, `pausada`, `completada`, `cancelada` | Cabecera `orden_trabajo` |
| `estado_ov` | `borrador`, `confirmada`, `en_preparacion`, `parcialmente_despachada`, `despachada`, `cerrada`, `cancelada` | Cabecera `orden_venta` |
| `estado_lote` | `activo`, `bloqueado`, `vencido`, `agotado` | Trazabilidad `lote` |
| `tipo_movimiento` | `recepcion`, `despacho`, `transferencia`, `ajuste_positivo`, `ajuste_negativo`, `reserva`, `liberacion_reserva`, `consumo_ot`, `produccion_ot` | `movimiento_inventario` |
| `tipo_linea_ot` | `entrada`, `salida`, `subproducto` | `linea_orden_trabajo` |
| `estado_viaje` | `programado`, `en_ruta`, `entregado`, `cancelado` | `viaje_transporte` |
| `estado_guia` | `generada`, `asignada`, `en_transito`, `entregada`, `anulada` | `guia_envio` |
| `tipo_auditoria` | `creacion`, `actualizacion`, `eliminacion`, `cambio_estado`, `movimiento_inventario`, `acceso_denegado` | `auditoria_operacion` |
| `nombre_contador` | `solicitud_compra`, `orden_compra`, `orden_trabajo`, `orden_venta`, `viaje_transporte`, `guia_envio`, `lote`, `movimiento_inventario` | Clave lógica en `contador` |

Enums reservados para líneas (evaluar en implementación si columnas `estado` por línea son necesarias en V2.1):

| Enum | Valores propuestos | Tabla |
|------|-------------------|-------|
| `estado_linea_oc` | `pendiente`, `parcial`, `completa`, `cancelada` | `linea_orden_compra` |
| `estado_linea_ov` | `pendiente`, `parcial`, `completa`, `cancelada` | `linea_orden_venta` |

---

## 3. Matriz tenant × canal de acceso

Leyenda:

| Símbolo | Significado |
|---------|-------------|
| **S** | SELECT vía PostgREST (`authenticated` + RLS) |
| **W** | INSERT/UPDATE/DELETE vía PostgREST (fase inicial: **no** en tablas operativas; mutaciones vía API backend) |
| **B** | Solo backend (`postgres` / service role); `REVOKE` explícito a `authenticated` |
| **—** | Sin exposición PostgREST en V2 inicial |

Política SELECT estándar para tablas **C**:

```sql
USING (auth_wms_puede_ver_cuenta(codigo_cuenta))
```

Política SELECT estándar para tablas **C+B**:

```sql
USING (
    auth_wms_puede_ver_cuenta(codigo_cuenta)
    AND auth_wms_puede_ver_bodega(id_bodega)
)
```

| Tabla | `codigo_cuenta` | `id_bodega` | SELECT PostgREST | Escritura PostgREST | Escritura backend |
|-------|:---------------:|:-----------:|:----------------:|:-------------------:|:-----------------:|
| `tipo_ubicacion` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `zona` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `ubicacion` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `proveedor` | ✓ FK | — | **S** | **—** | **W** |
| `cliente` | ✓ FK | — | **S** | **—** | **W** |
| `producto` | ✓ FK | — | **S** | **—** | **W** |
| `comprador` | ✓ FK | — | **S** | **—** | **W** |
| `planta` | ✓ FK | — | **S** | **—** | **W** |
| `camion` | ✓ FK | — | **S** | **—** | **W** |
| `solicitud_compra` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `linea_solicitud_compra` | *(vía padre)* | *(vía padre)* | **S** | **—** | **W** |
| `orden_compra` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `linea_orden_compra` | *(vía padre)* | *(vía padre)* | **S** | **—** | **W** |
| `lote` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `warehouse_state` | ✓ FK | ✓ FK | **S** | **B** | **B** |
| `movimiento_inventario` | ✓ FK | ✓ FK | **S** | **B** | **B** |
| `orden_trabajo` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `linea_orden_trabajo` | *(vía padre)* | *(vía padre)* | **S** | **—** | **W** |
| `orden_venta` | ✓ FK | ✓ FK | **S** | **—** | **W** |
| `linea_orden_venta` | *(vía padre)* | *(vía padre)* | **S** | **—** | **W** |
| `viaje_transporte` | ✓ FK | ✓ origen | **S** | **—** | **W** |
| `guia_envio` | ✓ FK | *(vía OV)* | **S** | **—** | **W** |
| `auditoria_operacion` | ✓ FK | ✓ nullable | **S** | **B** | **B** |
| `contador` | ✓ FK | ✓ nullable | **—** | **B** | **B** |

### Tablas excluidas (no POL-33)

No se crean ni alteran en este issue:

| Tabla | Motivo |
|-------|--------|
| `mateo_conversacion`, `mateo_historial`, `document_chunks`, `users`, `requirements` | Esquema Mateo; RLS y migraciones en issues aparte |
| `rol`, `empresa`, `cuenta`, `usuario`, `bodega`, `asignacion_bodega` | Ya definidas en POL-2 |

---

## 4. Plan de migraciones `020`–`030`

| # | Archivo | Contenido |
|---|---------|-----------|
| 020 | `020_operative_enums.sql` | Todos los enums de §2 |
| 021 | `021_layout_ubicaciones.sql` | `tipo_ubicacion`, `zona`, `ubicacion` + índices + triggers `updated_at` |
| 022 | `022_catalogos_maestros.sql` | `proveedor`, `cliente`, `producto` |
| 023 | `023_catalogos_auxiliares.sql` | `comprador`, `planta`, `camion` |
| 024 | `024_compras_solicitud.sql` | `solicitud_compra`, `linea_solicitud_compra` |
| 025 | `025_compras_orden.sql` | `orden_compra`, `linea_orden_compra` + FK opcional a solicitud |
| 026 | `026_inventario.sql` | `lote`, `warehouse_state`, `movimiento_inventario` + `REVOKE` escritura `authenticated` |
| 027 | `027_procesamiento_orden_trabajo.sql` | `orden_trabajo`, `linea_orden_trabajo` |
| 028 | `028_ventas_orden_venta.sql` | `orden_venta`, `linea_orden_venta` |
| 029 | `029_transporte.sql` | `viaje_transporte`, `guia_envio` |
| 030 | `030_rls_operativo.sql` | RLS SELECT en todas las tablas operativas; `GRANT SELECT`; políticas con `auth_wms_puede_ver_cuenta` / `auth_wms_puede_ver_bodega`; `REVOKE` final en sensibles; `contador` sin SELECT PostgREST |

Orden de dependencias:

```
020 → 021 → 022 → 023 → 024 → 025 → 026 → 027 → 028 → 029 → 030
         └──────────────────────────────────────────────────────┘
                    catálogos antes de documentos e inventario
```

Cada archivo en `migrations/` tendrá su espejo en `supabase/migrations/` (misma convención POL-2).

---

## 5. RLS y helpers reutilizados

Ver documentación completa en [Políticas RLS](rls-politicas.md).

### Funciones existentes (no recrear)

| Función | Uso en POL-33 |
|---------|---------------|
| `auth_wms_puede_ver_cuenta(codigo)` | Políticas SELECT en tablas **C** y validación de tenant comercial |
| `auth_wms_puede_ver_bodega(uuid)` | Políticas SELECT en tablas **C+B** y documentos anclados a bodega |
| `auth_wms_es_configurador()` | Sin cambio; escritura plataforma POL-2 |
| `auth_wms_usuario_actual()` | Contexto para auditoría y validaciones en backend |

### Patrón RLS para tablas operativas (migración `030`)

1. `ALTER TABLE … ENABLE ROW LEVEL SECURITY`
2. Política `{tabla}_select_scope` con predicado cuenta ± bodega
3. `GRANT SELECT ON {tabla} TO authenticated`
4. `REVOKE INSERT, UPDATE, DELETE ON {tabla} FROM authenticated` (tablas operativas y sensibles)
5. Tablas sensibles (`warehouse_state`, `movimiento_inventario`, `contador`, `auditoria_operacion`): escritura exclusiva backend

### Separación de responsabilidades

| Canal | Rol | Mutaciones operativas |
|-------|-----|----------------------|
| PostgREST / supabase-js | `authenticated` | Solo lectura acotada por RLS |
| `polaria-wms-api` | `postgres` (bypass RLS) | CRUD de negocio + inventario + contadores |

El backend **debe** validar en código `codigo_empresa`, `codigo_cuenta`, `id_bodega` y permisos del rol operativo aunque RLS no aplique.

---

## Referencias

- [POL-2 — Políticas RLS](rls-politicas.md)
- [Login fase 1](login-fase1.md) — auth, `usuario`, contexto de sesión
- [Integración Mateo](mateo-integracion-bd.md) — tablas excluidas
- [ADR-001 Multi-tenant](adr/ADR-001-multi-tenant.md)
- [ADR-003 RBAC](adr/ADR-003-rbac.md)
- Migración fundacional: `migrations/017_bodega_base.sql`

---

## Fuera de alcance V2 (issues futuros)

- Políticas INSERT/UPDATE/DELETE vía PostgREST para operadores (hoy todo vía API)
- RPC `SECURITY DEFINER` para operaciones atómicas de inventario
- Integración directa Mateo ↔ tablas operativas
- Sincronización Auth ↔ `usuario` (signup/onboarding)
- Claims JWT vía `app_metadata`
