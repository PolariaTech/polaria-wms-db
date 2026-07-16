# Integración Mateo — perspectiva de base de datos

## Qué es Mateo y cómo se relaciona con el WMS

**Mateo** es el asistente de inteligencia artificial de Polaria, desplegado en [chatbot-mateo.vercel.app](https://chatbot-mateo.vercel.app). Es una aplicación **independiente** del WMS: otro repositorio, otro despliegue y su propia lógica de chat.

El **Sistema de Gestión de Almacenes (WMS)** de Polaria se compone de tres repos:

| Repo | Rol |
|------|-----|
| [polaria-wms-db](https://github.com/PolariaTech/polaria-wms-db) (este) | Esquema PostgreSQL en Supabase |
| [polaria-wms-api](https://github.com/PolariaTech/polaria-wms-api) | Backend NestJS (auth, negocio, SSO Mateo, widget-token, conversaciones) |
| [polaria-wms-web](https://github.com/PolariaTech/polaria-wms-web) | Frontend Next.js (SSO + host del widget embebido) |
| [Widget-react](https://github.com/PolariaTech/Widget-react) | Bundle del chat flotante Mateo Support |

Hay **dos** integraciones Mateo:

1. **SSO handoff** (app Mateo full-page): JWT efímero firmado por el API; **esta BD no participa**.
2. **Widget embebido**: tablas `widget_conversacion` / `widget_mensaje` + `resolve_web_user` (migración `051`). Ver [WIDGET-MATEO-CONVERSACIONES.md](WIDGET-MATEO-CONVERSACIONES.md).

```
Usuario (WMS web) ──sesión──► polaria-wms-api
                                    │
                    ┌───────────────┼───────────────┐
                    │ JWT handoff   │ widget-token  │ REST conversaciones
                    ▼               ▼               ▼
              chatbot-mateo    n8n (POL-71)    widget_* (Supabase)
```

## Campos de `usuario` relevantes

La tabla `usuario` (migración `012_user.sql`) ya expone los identificadores que ambos mundos necesitan. No hay tablas ni columnas adicionales para Mateo.

| Campo | Tipo | Uso en WMS | Uso en Mateo |
|-------|------|------------|--------------|
| `correo` | `citext`, único | Login por correo en el WMS | Identidad de contacto / correlación |
| `username` | `citext`, único | Login por nombre de usuario (flujo empresa + username) | Identificador principal esperado por Mateo |
| `id_auth` | `uuid`, único, FK → `auth.users` | Vínculo 1:1 con Supabase Auth; sesión WMS y RLS | Misma identidad de autenticación subyacente |

Ambos flujos de login del WMS (correo o username) resuelven al mismo registro de `usuario` y al mismo `id_auth`. Mateo consume la identidad que el API obtiene de ese perfil al generar el JWT de handoff.

Índices existentes que ya cubren búsquedas de login (`ix_usuario_login_correo`, `ix_usuario_login_username`, `ix_usuario_id_auth`) siguen siendo válidos; no se requieren índices nuevos para Mateo.

## SSO sin persistencia en PostgreSQL

El handoff **no guarda nada en esta base de datos**:

- No hay tabla de códigos temporales, tokens de un solo uso ni sesiones de Mateo en `public`.
- El “código” que recibe Mateo es un **JWT firmado por el API** (clave y TTL configurados en el backend, no en migraciones SQL).
- La validación, el canje y la sesión en Mateo son responsabilidad del API y de la app Mateo.

Desde la perspectiva de **polaria-wms-db**, el SSO es transparente: los datos de identidad ya viven en `usuario` + `auth.users`; el puente es lógica de aplicación.

## ¿Se requiere migración?

**Para SSO handoff: no.** El esquema de fase 1 sigue bastando (`usuario` + Auth).

**Para el widget Mateo embebido (persistencia de chat): sí.** Ver [WIDGET-MATEO-CONVERSACIONES.md](WIDGET-MATEO-CONVERSACIONES.md) y la migración `051_widget_mateo_conversaciones.sql` (`widget_conversacion` / `widget_mensaje` + RLS + `resolve_web_user`).

Si en el futuro Mateo necesitara **auditoría** de handoffs o **preferencias** guardadas en el WMS, eso sería un cambio de producto explícito y una migración nueva; el handoff en sí no persiste en PostgreSQL.

## Documentación relacionada

- [Login — Fase 1](login-fase1.md) — esquema `usuario`, Auth y reglas de login WMS.
- [Widget Mateo — conversaciones](WIDGET-MATEO-CONVERSACIONES.md) — tablas, RLS, n8n, retención.
- [polaria-wms-api](https://github.com/PolariaTech/polaria-wms-api) — handoff JWT, widget-token y REST de conversaciones.
- [polaria-wms-web](https://github.com/PolariaTech/polaria-wms-web) — UI SSO y host del widget embebido.
