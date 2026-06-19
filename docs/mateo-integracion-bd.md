# Integración Mateo — perspectiva de base de datos

## Qué es Mateo y cómo se relaciona con el WMS

**Mateo** es el asistente de inteligencia artificial de Polaria, desplegado en [chatbot-mateo.vercel.app](https://chatbot-mateo.vercel.app). Es una aplicación **independiente** del WMS: otro repositorio, otro despliegue y su propia lógica de chat.

El **Sistema de Gestión de Almacenes (WMS)** de Polaria se compone de tres repos:

| Repo | Rol |
|------|-----|
| [polaria-wms-db](https://github.com/PolariaTech/polaria-wms-db) (este) | Esquema PostgreSQL en Supabase |
| [polaria-wms-api](https://github.com/PolariaTech/polaria-wms-api) | Backend NestJS (auth, negocio, handoff a Mateo) |
| [polaria-wms-web](https://github.com/PolariaTech/polaria-wms-web) | Frontend Next.js |

La integración planificada permite que un usuario **ya autenticado en el WMS** abra Mateo sin volver a iniciar sesión. El flujo es **SSO por handoff**: el API genera un código temporal (JWT firmado) que Mateo valida y convierte en sesión propia. Ese intercambio ocurre entre **API ↔ Mateo**; esta base de datos no participa en el handoff.

```
Usuario (WMS web) ──sesión──► polaria-wms-api
                                    │
                                    │ JWT de handoff (firmado, efímero)
                                    ▼
                              chatbot-mateo.vercel.app
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

**No.** El esquema actual de fase 1 es suficiente:

- `usuario` con `correo`, `username` e `id_auth` cubre identidad WMS y handoff a Mateo.
- No hay hueco funcional que obligue a nuevas tablas, columnas, enums ni políticas RLS específicas de Mateo.
- Cualquier secreto de firma del JWT, URL de Mateo o TTL del token pertenece al **API** (variables de entorno), no a este repo.

Si en el futuro Mateo necesitara **auditoría** de handoffs o **preferencias** guardadas en el WMS, eso sería un cambio de producto explícito y una migración nueva; hoy no está en alcance.

## Documentación relacionada

- [Login — Fase 1](login-fase1.md) — esquema `usuario`, Auth y reglas de login WMS.
- [polaria-wms-api](https://github.com/PolariaTech/polaria-wms-api) — implementación del endpoint de handoff y firma JWT.
- [polaria-wms-web](https://github.com/PolariaTech/polaria-wms-web) — UI que enlaza al chatbot tras login.
