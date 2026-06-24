-- =============================================================================
-- Migración 015: RLS completo — aislamiento por tenant (POL-2)
-- =============================================================================
-- Scope: polaria-wms-db / Supabase (proyecto zmdokvjewvqaftnvulsr)
-- Issue: POL-2 — Configurar multi-tenant y RLS base en Supabase
--
-- Diseño multi-tenant de Polaria WMS:
--   empresa (codigo_empresa) → cuenta (codigo_cuenta) → usuario
--
-- Roles y su nivel de acceso:
--   configurador      → plataforma: ve y puede operar todo
--   cuenta/bodega     → tenant: solo su codigo_cuenta
--
-- Regla de escrituras:
--   NO existen políticas INSERT/UPDATE/DELETE en este schema.
--   Todas las escrituras se ejecutan desde polaria-wms-api usando la
--   conexión directa Postgres (DATABASE_URL) que bypasea RLS con el rol postgres.
--   Las escrituras directas desde el cliente Supabase están bloqueadas por diseño.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. SCHEMA app — funciones helper para RLS (no expuesto a la API pública)
-- ---------------------------------------------------------------------------
-- El schema `app` contiene funciones SECURITY DEFINER que las políticas RLS
-- usan para leer el contexto del usuario autenticado eficientemente.
-- Solo el rol `authenticated` tiene acceso (anon queda excluido).

CREATE SCHEMA IF NOT EXISTS app;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
REVOKE ALL ON SCHEMA app FROM anon;
GRANT USAGE ON SCHEMA app TO authenticated;

-- Retorna el id_rol del usuario actual
CREATE OR REPLACE FUNCTION app.current_rol()
RETURNS wms_rol
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT u.id_rol FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo LIMIT 1;
$$;

-- Retorna el codigo_empresa del usuario actual
CREATE OR REPLACE FUNCTION app.current_codigo_empresa()
RETURNS varchar
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT u.codigo_empresa FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo LIMIT 1;
$$;

-- Retorna el codigo_cuenta del usuario actual
CREATE OR REPLACE FUNCTION app.current_codigo_cuenta()
RETURNS varchar
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT u.codigo_cuenta FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo LIMIT 1;
$$;

-- Verifica si el usuario actual es configurador (rol plataforma)
CREATE OR REPLACE FUNCTION app.is_configurador()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT EXISTS (
        SELECT 1 FROM usuario u
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND u.id_rol = 'configurador'
    );
$$;

-- Verifica si el usuario puede acceder a una empresa dada
CREATE OR REPLACE FUNCTION app.has_empresa_access(p_codigo_empresa varchar)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT app.is_configurador()
        OR (p_codigo_empresa IS NOT NULL AND p_codigo_empresa = app.current_codigo_empresa());
$$;

-- Verifica si el usuario puede acceder a una cuenta dada
CREATE OR REPLACE FUNCTION app.has_cuenta_access(p_codigo_cuenta varchar)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT app.is_configurador()
        OR (p_codigo_cuenta IS NOT NULL AND p_codigo_cuenta = app.current_codigo_cuenta());
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. FUNCIÓN set_updated_at — corregir search_path mutable (advisor seguridad)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


-- ---------------------------------------------------------------------------
-- 3. TABLA rol — política ya correcta desde 010_roles.sql (solo comentario)
-- ---------------------------------------------------------------------------

COMMENT ON POLICY rol_select_authenticated ON public.rol IS
    'Catálogo fijo del sistema. Lectura para todos los authenticated. '
    'Sin política de escritura: el catálogo solo se modifica por migraciones.';


-- ---------------------------------------------------------------------------
-- 4. TABLA empresa — actualizar política con funciones app.*
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS empresa_select_scope ON public.empresa;

CREATE POLICY empresa_select_scope
    ON public.empresa
    FOR SELECT
    TO authenticated
    USING (app.has_empresa_access(codigo_empresa));

COMMENT ON POLICY empresa_select_scope ON public.empresa IS
    'Aislamiento empresa: configurador ve todas; otros usuarios solo ven su empresa. '
    'Sin política de escritura: solo backend (service role).';


-- ---------------------------------------------------------------------------
-- 5. TABLA cuenta — aislamiento empresa con funciones app.*
-- ---------------------------------------------------------------------------
-- Usa has_empresa_access (empresa-level) en Fase 1.
-- Cuando existan bodegas, migrar a has_cuenta_access para aislamiento estricto.

DROP POLICY IF EXISTS cuenta_select_scope ON public.cuenta;

CREATE POLICY cuenta_select_scope
    ON public.cuenta
    FOR SELECT
    TO authenticated
    USING (app.has_empresa_access(codigo_empresa));

COMMENT ON POLICY cuenta_select_scope ON public.cuenta IS
    'Fase 1: aislamiento por empresa (configurador ve todo; otros ven cuentas de su empresa). '
    'Fase 2: migrar a app.has_cuenta_access(codigo_cuenta) para aislamiento estricto por tenant. '
    'Sin política de escritura: solo backend (service role).';


-- ---------------------------------------------------------------------------
-- 6. TABLA usuario — aislamiento por codigo_cuenta con funciones app.*
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS usuario_select_own   ON public.usuario;
DROP POLICY IF EXISTS usuario_select_scope ON public.usuario;

CREATE POLICY usuario_select_scope
    ON public.usuario
    FOR SELECT
    TO authenticated
    USING (
        -- Siempre puede verse a sí mismo
        id_auth = auth.uid()
        -- Configurador ve todos los usuarios
        OR app.is_configurador()
        -- Roles con cuenta: ven compañeros del mismo tenant
        OR (
            codigo_cuenta IS NOT NULL
            AND codigo_cuenta = app.current_codigo_cuenta()
        )
        -- Roles sin cuenta asignada: ven usuarios de su empresa (administrador en onboarding)
        OR (
            app.current_codigo_cuenta() IS NULL
            AND codigo_empresa IS NOT NULL
            AND codigo_empresa = app.current_codigo_empresa()
        )
    );

COMMENT ON POLICY usuario_select_scope ON public.usuario IS
    'Aislamiento tenant: propio row siempre visible; configurador ve todos; '
    'roles con cuenta ven compañeros del mismo tenant; roles sin cuenta (onboarding) '
    'ven usuarios de su empresa. Sin política de escritura: solo backend (service role). '
    'Nota: id_bodega se añadirá en Fase 2 con migraciones de asignacion_bodega.';


-- ---------------------------------------------------------------------------
-- 7. TABLA document_chunks — habilitar RLS (RAG de Mateo Support)
-- ---------------------------------------------------------------------------
-- Estaba completamente expuesta. Se habilita RLS y se permite solo lectura
-- para authenticated (para llamadas a match_documents). Escritura solo desde
-- backend (service role, n8n).

ALTER TABLE public.document_chunks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_chunks_select_authenticated ON public.document_chunks;

CREATE POLICY document_chunks_select_authenticated
    ON public.document_chunks
    FOR SELECT
    TO authenticated
    USING (true);

COMMENT ON TABLE public.document_chunks IS
    'Chunks de documentos para RAG de Mateo Support. RLS activo: lectura para '
    'usuarios autenticados (vía match_documents RPC); escritura solo desde service role (n8n/backend).';


-- ---------------------------------------------------------------------------
-- 8. FUNCIONES Mateo — corregir search_path mutable (advisor seguridad)
-- ---------------------------------------------------------------------------
-- Las funciones de triggers de mateo_historial y match_documents tenían
-- search_path sin fijar, lo que permite inyección de schema. Se corrige
-- añadiendo SET search_path = public.

CREATE OR REPLACE FUNCTION public.match_documents(
    query_embedding vector,
    match_count integer DEFAULT 5,
    filter jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(id bigint, content text, metadata jsonb, similarity double precision)
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    document_chunks.id,
    document_chunks.content,
    document_chunks.metadata,
    1 - (document_chunks.embedding <=> query_embedding) AS similarity
  FROM document_chunks
  WHERE document_chunks.metadata @> filter
  ORDER BY document_chunks.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_mateo_historial_set_secuencia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF new.secuencia IS NULL OR new.secuencia = 0 THEN
    SELECT COALESCE(MAX(secuencia), 0) + 1
    INTO new.secuencia
    FROM public.mateo_historial
    WHERE id_conversacion = new.id_conversacion;
  END IF;
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_mateo_historial_set_titulo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF new.rol = 'user' THEN
    UPDATE public.mateo_conversacion
    SET titulo = LEFT(new.contenido, 120)
    WHERE id_conversacion = new.id_conversacion
      AND titulo IS NULL;
  END IF;
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_mateo_historial_touch_conversacion()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.mateo_conversacion
  SET updated_at = now()
  WHERE id_conversacion = new.id_conversacion;
  RETURN new;
END;
$$;


-- ---------------------------------------------------------------------------
-- 9. TABLAS users / requirements (Mateo Support) — documentar intención
-- ---------------------------------------------------------------------------
-- RLS habilitado SIN políticas = bloqueo total para authenticated/anon.
-- Acceso únicamente vía service role (n8n). Diseño intencional.

COMMENT ON TABLE public.users IS
    'Solicitantes externos (WhatsApp) que crean requerimientos en Linear. '
    'RLS activo sin políticas: acceso solo desde service role (n8n). '
    'No confundir con public.usuario (usuarios WMS internos con auth.users).';

COMMENT ON TABLE public.requirements IS
    'Relación entre un issue de Linear y el usuario solicitante de Mateo Support. '
    'RLS activo sin políticas: acceso solo desde service role (n8n).';
