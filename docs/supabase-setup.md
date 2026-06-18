# Conectar polaria-wms-db con Supabase

Este repo es **solo base de datos** (migraciones SQL). La ventana *Connect to your project → Framework / Next.js* es para apps frontend; **no la uses aquí**.

**Proyecto configurado:** `zmdokvjewvqaftnvulsr`

## Forma más rápida (un comando)

En PowerShell, desde la raíz del repo:

```powershell
.\scripts\apply-remote-migrations.ps1
```

Te pedirá la **contraseña de la base de datos** y abrirá el navegador para `supabase login`. Luego enlaza el repo y ejecuta `db push`.

## Qué necesitas del dashboard

1. **Project ref** — ya es `zmdokvjewvqaftnvulsr`.
2. **Contraseña de la base de datos** (Settings → Database).  
   Host: `db.zmdokvjewvqaftnvulsr.supabase.co`, puerto `5432`, user `postgres`.
3. **Opcional** (apps frontend): URL y publishable key en Settings → API.

## Pasos manuales (equivalente al script)

```powershell
npx supabase login
npx supabase link --project-ref zmdokvjewvqaftnvulsr -p "TU_CONTRASEÑA"
npx supabase db push
```

Tras `db push`, en **Table Editor**: `rol`, `empresa`, `usuario`, `cuenta`.

## Verificar

SQL Editor:

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('rol', 'empresa', 'usuario', 'cuenta');

SELECT COUNT(*) FROM rol;  -- debe ser 9
```

## Estructura en el repo

- `migrations/` — SQL fuente (001 … 013)
- `supabase/migrations/` — enlace al mismo folder (para el CLI)
- `supabase/config.toml` — config local del CLI

## Alternativa sin CLI

SQL Editor → pegar y ejecutar en orden:

`001_extensions.sql` → `002_enums.sql` → `010_roles.sql` → `011_company.sql` → `012_user.sql` → `013_account.sql`

(No ejecutar `scripts/bootstrap-auth.sql` en Supabase; `auth.users` ya existe.)

## MCP en Cursor (opcional)

En la ventana *Connect* puedes usar la pestaña **MCP** para que el agente ejecute SQL en tu proyecto. Requiere autenticar el plugin Supabase en Cursor Settings → MCP.
