-- Mover widget_conversacion / widget_mensaje de public a mateo_support.
-- Prisma (Nest) y PostgREST siguen operando tras grants + pgrst.db_schemas.

CREATE SCHEMA IF NOT EXISTS mateo_support;

COMMENT ON SCHEMA mateo_support IS
    'Persistencia del widget Mateo Support (conversaciones / mensajes).';

GRANT USAGE ON SCHEMA mateo_support TO anon, authenticated, service_role;

-- Mover tablas (índices, constraints, RLS y policies viajan con ellas).
ALTER TABLE IF EXISTS public.widget_mensaje SET SCHEMA mateo_support;
ALTER TABLE IF EXISTS public.widget_conversacion SET SCHEMA mateo_support;

-- Policies de mensaje referencian widget_conversacion sin schema;
-- recrear con nombres calificados para no depender del search_path.
DROP POLICY IF EXISTS widget_mensaje_select_own ON mateo_support.widget_mensaje;
DROP POLICY IF EXISTS widget_mensaje_insert_own ON mateo_support.widget_mensaje;
DROP POLICY IF EXISTS widget_mensaje_update_own ON mateo_support.widget_mensaje;
DROP POLICY IF EXISTS widget_mensaje_delete_own ON mateo_support.widget_mensaje;

CREATE POLICY widget_mensaje_select_own
    ON mateo_support.widget_mensaje
    FOR SELECT
    TO authenticated
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM mateo_support.widget_conversacion c
            INNER JOIN public.usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_mensaje_insert_own
    ON mateo_support.widget_mensaje
    FOR INSERT
    TO authenticated
    WITH CHECK (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM mateo_support.widget_conversacion c
            INNER JOIN public.usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_mensaje_update_own
    ON mateo_support.widget_mensaje
    FOR UPDATE
    TO authenticated
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM mateo_support.widget_conversacion c
            INNER JOIN public.usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    )
    WITH CHECK (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM mateo_support.widget_conversacion c
            INNER JOIN public.usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

CREATE POLICY widget_mensaje_delete_own
    ON mateo_support.widget_mensaje
    FOR DELETE
    TO authenticated
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion
            FROM mateo_support.widget_conversacion c
            INNER JOIN public.usuario u ON u.id_usuario = c.id_usuario
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
        )
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA mateo_support
    TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA mateo_support
    TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mateo_support
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA mateo_support
    GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- Exponer el schema en la Data API (PostgREST).
ALTER ROLE authenticator SET pgrst.db_schemas = 'public, graphql_public, mateo_support';
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
