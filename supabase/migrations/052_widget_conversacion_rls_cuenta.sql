-- POL-138 / POL-174: endurecer RLS de widget_conversacion — codigo_cuenta alineado al tenant.
--
-- Antes: solo se validaba id_usuario = auth.uid(); codigo_cuenta podía spoofearse vía PostgREST.
-- Ahora: codigo_cuenta debe ser NULL o visible con auth_wms_puede_ver_cuenta y coherente con usuario.

GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_cuenta(varchar) TO authenticated;

DROP POLICY IF EXISTS widget_conversacion_insert_own ON widget_conversacion;
DROP POLICY IF EXISTS widget_conversacion_update_own ON widget_conversacion;

CREATE POLICY widget_conversacion_insert_own
    ON widget_conversacion
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
              AND u.id_usuario = widget_conversacion.id_usuario
              AND (
                  widget_conversacion.codigo_cuenta IS NULL
                  OR (
                      auth_wms_puede_ver_cuenta(widget_conversacion.codigo_cuenta)
                      AND (
                          u.codigo_cuenta IS NULL
                          OR u.codigo_cuenta = widget_conversacion.codigo_cuenta
                      )
                  )
              )
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
        EXISTS (
            SELECT 1
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
              AND u.id_usuario = widget_conversacion.id_usuario
              AND (
                  widget_conversacion.codigo_cuenta IS NULL
                  OR (
                      auth_wms_puede_ver_cuenta(widget_conversacion.codigo_cuenta)
                      AND (
                          u.codigo_cuenta IS NULL
                          OR u.codigo_cuenta = widget_conversacion.codigo_cuenta
                      )
                  )
              )
        )
    );

COMMENT ON POLICY widget_conversacion_insert_own ON widget_conversacion IS
    'POL-138: dueño por id_usuario + codigo_cuenta coherente con tenant del caller.';
