-- POL-2: reemplazar política legacy usuario_select_scope (app.* / Mateo) por usuario_select_own.
-- usuario_select_scope_admin (016) cubre configurador y administrador_cuenta.
-- No toca document_chunks ni funciones app.* de Mateo.

DROP POLICY IF EXISTS usuario_select_scope ON usuario;

DROP POLICY IF EXISTS usuario_select_own ON usuario;

CREATE POLICY usuario_select_own
    ON usuario
    FOR SELECT
    TO authenticated
    USING (id_auth = auth.uid());
