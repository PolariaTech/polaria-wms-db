# Login — Fase 1 (base de datos)

Esquema mínimo para autenticación en Supabase, alineado al modelo funcional de Polaria ([flujos](https://github.com/eldani13/flujos)).

## Diagrama de relaciones

```
auth.users (Supabase Auth — contraseñas)
    │
    │ 1:1 id_auth
    ▼
usuario ──N:1──► rol (catálogo fijo, 9 roles)
    │
    ├──N:1──► empresa (codigo_empresa; NULL solo configurador)
    │
    └──N:1──► cuenta (codigo_cuenta; NULL en configurador y opcional en admin cuenta)

empresa 1───* cuenta
    ▲
    └── id_creador ──► usuario (configurador TI)
```

Flujo de login:

1. **Usuario / empresa** — validar `empresa.esta_activa` y que `usuario.codigo_empresa` coincida (excepto configurador).
2. **Contraseña** — `auth.users` vía Supabase Auth (no se guarda en tablas de negocio).
3. **Sesión** — tras Auth, cargar `id_rol`, `codigo_empresa`, `codigo_cuenta` desde `usuario` para contexto y RLS.

## Tablas implementadas

| Tabla | Propósito |
|-------|-----------|
| `rol` | Catálogo fijo de 9 perfiles WMS |
| `empresa` | Cliente jurídico del SaaS |
| `cuenta` | Tenant operativo bajo una empresa |
| `usuario` | Perfil operativo vinculado a `auth.users` |

## Reglas de negocio

- **configurador (TI)**: `codigo_empresa` y `codigo_cuenta` deben ser `NULL`.
- **Usuarios cliente**: `codigo_empresa` obligatorio (`CHECK chk_usuario_contexto`).
- **administrador_cuenta**: puede tener `codigo_cuenta` `NULL` hasta asignación de tenant.
- **Correo** (`citext`) y **username** (`citext`) únicos para login por correo o nombre de usuario.
- **Contraseñas**: solo en `auth.users`; `usuario.id_auth` es la integración 1:1.
- **Autorización**: no usar `user_metadata`; el rol vive en `usuario.id_rol`.
- **RLS**: habilitado en todas las tablas expuestas; políticas mínimas de solo lectura acotada.

## Índices de login

- `uq_usuario_correo`, `uq_usuario_username`
- `ix_usuario_login_username`, `ix_usuario_login_correo` (parciales, `esta_activo`)
- `ix_usuario_id_auth`, `ix_usuario_empresa`, `ix_usuario_cuenta`, `ix_usuario_rol`
- FKs indexadas en `empresa`, `cuenta`

## Consultas de prueba

### 1. Catálogo de roles (esperado: 9 filas)

```sql
SELECT id_rol, nombre, nivel
FROM rol
ORDER BY nivel, id_rol;
```

### 2. Resolver login V2 por empresa + username (pre-Auth)

```sql
SELECT u.id_usuario, u.id_auth, u.id_rol, u.codigo_empresa, u.codigo_cuenta, e.esta_activa
FROM usuario u
JOIN empresa e ON e.codigo_empresa = u.codigo_empresa
WHERE e.codigo_empresa = 'ACME'
  AND u.username = 'admin.acme'
  AND u.esta_activo
  AND e.esta_activa;
```

### 3. Contexto de sesión post-Auth (por `auth.uid()`)

```sql
SELECT
    u.id_usuario,
    u.nombre,
    u.username,
    u.correo,
    r.id_rol,
    r.nombre AS rol_nombre,
    r.nivel AS rol_nivel,
    u.codigo_empresa,
    u.codigo_cuenta,
    e.razon_social,
    c.nombre_comercial AS cuenta_nombre
FROM usuario u
JOIN rol r ON r.id_rol = u.id_rol
LEFT JOIN empresa e ON e.codigo_empresa = u.codigo_empresa
LEFT JOIN cuenta c ON c.codigo_cuenta = u.codigo_cuenta
WHERE u.id_auth = auth.uid()
  AND u.esta_activo;
```

### 4. Login plataforma (configurador, sin empresa)

```sql
SELECT u.id_usuario, u.id_auth, u.id_rol, u.codigo_empresa, u.codigo_cuenta
FROM usuario u
WHERE u.username = 'ti.config'
  AND u.id_rol = 'configurador'
  AND u.esta_activo;
```

### 5. Validar restricción de contexto

```sql
-- Debe fallar: cliente sin empresa
INSERT INTO usuario (id_auth, id_rol, nombre, username, correo)
VALUES (gen_random_uuid(), 'operador_cuenta', 'X', 'x', 'x@test.com');
-- ERROR: chk_usuario_contexto
```

## Qué quedó listo (fase 1)

- Extensiones (`citext`, `pgcrypto`, `uuid-ossp`)
- Enums `wms_rol`, `rol_nivel`
- Tablas `rol`, `empresa`, `usuario`, `cuenta` en 3NF
- Semilla de 9 roles
- Integración `usuario.id_auth` → `auth.users`
- RLS y políticas SELECT mínimas
- Índices para búsqueda de login

## Integración con Mateo (chatbot IA)

Los campos `correo`, `username` e `id_auth` de `usuario` también alimentan el SSO hacia Mateo. El handoff no persiste datos en PostgreSQL; el API emite un JWT efímero. Detalle en [Integración Mateo — base de datos](mateo-integracion-bd.md).

## Fase 2 (fuera de alcance)

- `asignacion_bodega`, bodegas, solicitud de alta
- Catálogos operativos (proveedor, producto, etc.)
- Compras, ventas, inventario en vivo (`warehouse_state`)
- Políticas RLS de escritura por rol
- Triggers de sincronización Auth ↔ `usuario` (signup/onboarding)
- Funciones RPC de onboarding (crear empresa + admin + cuenta)
- Claims JWT vía `app_metadata` (si se adopta en backend)
