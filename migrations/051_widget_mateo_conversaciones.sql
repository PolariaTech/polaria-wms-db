-- Widget Mateo Support — conversaciones persistidas (canal web embebido en WMS).
-- Fuente de verdad: PostgreSQL (no localStorage en producción).
-- JWT widget: sub = usuario.id_auth; ownership vía id_usuario.

-- ---------------------------------------------------------------------------
-- widget_conversacion
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS widget_conversacion (
    id_conversacion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario      uuid NOT NULL REFERENCES usuario (id_usuario) ON DELETE CASCADE,
    codigo_cuenta   varchar(32) REFERENCES cuenta (codigo_cuenta),
    titulo          varchar(255),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_widget_conversacion_usuario_updated
    ON widget_conversacion (id_usuario, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_widget_conversacion_cuenta_updated
    ON widget_conversacion (codigo_cuenta, updated_at DESC)
    WHERE codigo_cuenta IS NOT NULL;

COMMENT ON TABLE widget_conversacion IS
    'Conversaciones del widget Mateo Support embebido en Polaria WMS (canal web).';
COMMENT ON COLUMN widget_conversacion.codigo_cuenta IS
    'Denormalizado desde usuario.codigo_cuenta para filtros/RLS tenant; NULL en scope plataforma.';

-- ---------------------------------------------------------------------------
-- widget_mensaje
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS widget_mensaje (
    id_mensaje      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_conversacion uuid NOT NULL REFERENCES widget_conversacion (id_conversacion) ON DELETE CASCADE,
    rol             varchar(10) NOT NULL,
    tipo            varchar(10) NOT NULL DEFAULT 'text',
    contenido       text NOT NULL,
    es_error        boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_widget_mensaje_rol CHECK (rol IN ('user', 'ai')),
    CONSTRAINT chk_widget_mensaje_tipo CHECK (tipo IN ('text', 'image'))
);

CREATE INDEX IF NOT EXISTS idx_widget_mensaje_conversacion_created
    ON widget_mensaje (id_conversacion, created_at ASC);

COMMENT ON TABLE widget_mensaje IS
    'Mensajes de widget_conversacion. contenido = texto o URL Cloudinary (tipo image).';
COMMENT ON COLUMN widget_mensaje.created_at IS
    'Timestamp del mensaje; el cliente/API puede mapear el timestamp del widget.';

-- ---------------------------------------------------------------------------
-- RLS — dueño = auth.uid() → usuario.id_auth
-- Service role (Nest DATABASE_URL / n8n con service role) bypassa RLS.
-- ---------------------------------------------------------------------------
ALTER TABLE widget_conversacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE widget_mensaje ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS widget_conversacion_select_own ON widget_conversacion;
DROP POLICY IF EXISTS widget_conversacion_insert_own ON widget_conversacion;
DROP POLICY IF EXISTS widget_conversacion_update_own ON widget_conversacion;
DROP POLICY IF EXISTS widget_conversacion_delete_own ON widget_conversacion;

CREATE POLICY widget_conversacion_select_own
    ON widget_conversacion
    FOR SELECT
    TO authenticated
    USING (
        id_usuario IN (
            SELECT u.id_usuario
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_conversacion_insert_own
    ON widget_conversacion
    FOR INSERT
    TO authenticated
    WITH CHECK (
        id_usuario IN (
            SELECT u.id_usuario
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_conversacion_update_own
    ON widget_conversacion
    FOR UPDATE
    TO authenticated
    USING (
        id_usuario IN (
            SELECT u.id_usuario
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    )
    WITH CHECK (
        id_usuario IN (
            SELECT u.id_usuario
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_conversacion_delete_own
    ON widget_conversacion
    FOR DELETE
    TO authenticated
    USING (
        id_usuario IN (
            SELECT u.id_usuario
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

DROP POLICY IF EXISTS widget_mensaje_select_own ON widget_mensaje;
DROP POLICY IF EXISTS widget_mensaje_insert_own ON widget_mensaje;
DROP POLICY IF EXISTS widget_mensaje_update_own ON widget_mensaje;
DROP POLICY IF EXISTS widget_mensaje_delete_own ON widget_mensaje;

CREATE POLICY widget_mensaje_select_own
    ON widget_mensaje
    FOR SELECT
    TO authenticated
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM widget_conversacion c
            INNER JOIN usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_mensaje_insert_own
    ON widget_mensaje
    FOR INSERT
    TO authenticated
    WITH CHECK (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM widget_conversacion c
            INNER JOIN usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_mensaje_update_own
    ON widget_mensaje
    FOR UPDATE
    TO authenticated
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM widget_conversacion c
            INNER JOIN usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    )
    WITH CHECK (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM widget_conversacion c
            INNER JOIN usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_mensaje_delete_own
    ON widget_mensaje
    FOR DELETE
    TO authenticated
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM widget_conversacion c
            INNER JOIN usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

-- ---------------------------------------------------------------------------
-- POL-71 — resolver id_auth (JWT widget sub) → id_usuario para n8n
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_web_user(p_id_auth uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.id_usuario
    FROM usuario u
    WHERE u.id_auth = p_id_auth
      AND u.esta_activo
    LIMIT 1
$$;

COMMENT ON FUNCTION resolve_web_user(uuid) IS
    'POL-71: resuelve sub del JWT widget Mateo (id_auth) a id_usuario WMS. Uso n8n/service role.';

REVOKE ALL ON FUNCTION resolve_web_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_web_user(uuid) TO service_role;
-- authenticated no necesita RPC pública; el API Nest usa DATABASE_URL (bypass RLS).
