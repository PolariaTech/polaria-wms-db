# Widget Mateo — conversaciones (persistencia)

Fuente de verdad en **PostgreSQL / Supabase**. No usar `localStorage` como almacén de producción.

Migración: [`migrations/051_widget_mateo_conversaciones.sql`](../migrations/051_widget_mateo_conversaciones.sql)  
Espejo Supabase CLI: [`supabase/migrations/051_widget_mateo_conversaciones.sql`](../supabase/migrations/051_widget_mateo_conversaciones.sql)

**Estado:** aplicada en el proyecto Supabase de desarrollo (`widget_conversacion` / `widget_mensaje` + `resolve_web_user`).

## Modelo

```
usuario (id_usuario, id_auth, codigo_cuenta)
    │ 1
    │
    ▼ N
widget_conversacion
    │ 1
    │
    ▼ N
widget_mensaje
```

| Tabla | Rol |
|-------|-----|
| `widget_conversacion` | Hilo de chat por usuario WMS |
| `widget_mensaje` | Turnos `user` / `ai` (texto o imagen) |

### `widget_conversacion`

| Columna | Notas |
|---------|--------|
| `id_conversacion` | UUID PK |
| `id_usuario` | FK → `usuario` ON DELETE CASCADE |
| `codigo_cuenta` | Denormalizado (tenant / listados); NULL en scope plataforma |
| `titulo` | Opcional |
| `created_at` / `updated_at` | Timestamptz |

Índice principal: `(id_usuario, updated_at DESC)`.

### `widget_mensaje`

Alineado al formato del widget (`role`, `type`, `content`, `timestamp`, `isError`):

| Columna | Widget | Notas |
|---------|--------|--------|
| `rol` | `role` | `'user'` \| `'ai'` |
| `tipo` | `type` | `'text'` \| `'image'` |
| `contenido` | `content` | Texto o URL Cloudinary |
| `es_error` | `isError` | Default `false` |
| `created_at` | `timestamp` | Mapeo desde el cliente/API |

Índice: `(id_conversacion, created_at ASC)`.

## RLS

- RLS habilitado en ambas tablas.
- Políticas `TO authenticated`: el `id_usuario` (o la conversación dueña del mensaje) debe pertenecer a `usuario` con `id_auth = auth.uid()` y `esta_activo`.
- **Service role** / conexión Prisma del API (`DATABASE_URL` como `postgres`) **bypassa RLS** — escrituras Nest y n8n con service role no dependen de estas políticas.

## Relación con n8n (POL-71)

1. El host WMS obtiene JWT vía `POST /auth/mateo/widget-token`.
2. n8n valida `Authorization: Bearer` con el **mismo** `MATEO_WIDGET_JWT_SECRET`, más `iss` / `aud` / `kid` (defaults: `bodega-frio-v2` / `mateo-support-widget` / `local-dev-v1`).
3. `sub` del JWT = `usuario.id_auth`.
4. Función RPC: `resolve_web_user(p_id_auth uuid) → id_usuario` (SECURITY DEFINER, grant a `service_role`).
5. Persistencia del hilo en UI: API Nest (`/mateo/conversaciones`) con Bearer de **sesión WMS** (no el JWT de n8n).

## Retención de datos

| Tema | Política sugerida |
|------|-------------------|
| Dueño | Soft-delete no definido; `DELETE` físico de conversación cascada a mensajes |
| Baja de usuario | `ON DELETE CASCADE` desde `usuario` |
| Imágenes | `contenido` guarda URL; ciclo de vida en Cloudinary es independiente |
| Retención temporal | No hay TTL en BD; si producto exige purge (ej. 90 días), job aparte sobre `updated_at` |

## Índices (resumen)

- `idx_widget_conversacion_usuario_updated` — listado por usuario ordenado por actividad
- `idx_widget_conversacion_cuenta_updated` — parcial por cuenta (tenant)
- `idx_widget_mensaje_conversacion_created` — timeline del hilo

## Docs relacionadas

- [mateo-integracion-bd.md](mateo-integracion-bd.md) — SSO handoff (sin tablas)
- polaria-wms-api: `docs/MATEO-INTEGRATION.md` — JWT widget + REST conversaciones
- polaria-wms-web: `docs/MATEO-WIDGET.md` — host del chat flotante
- Widget-react: `docs/EMBED-POLARIA.md` — bundle embebible
