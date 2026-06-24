-- POL-2: políticas de escritura para plataforma (solo configurador).
--
-- Backend API: conecta con DATABASE_URL (rol postgres / service) y bypass RLS.
-- Debe validar tenant (codigo_empresa, codigo_cuenta, id_bodega) en código de aplicación.
-- PostgREST (JWT authenticated): clientes solo lectura acotada; escritura plataforma = configurador TI.

-- Defensa en profundidad: revocar escritura antes de GRANTs selectivos.
REVOKE INSERT, UPDATE, DELETE ON rol FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON empresa FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON cuenta FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON usuario FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON bodega FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON asignacion_bodega FROM authenticated;

-- ---------------------------------------------------------------------------
-- empresa
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS empresa_insert_configurador ON empresa;
DROP POLICY IF EXISTS empresa_update_configurador ON empresa;

CREATE POLICY empresa_insert_configurador
    ON empresa
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY empresa_update_configurador
    ON empresa
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON empresa TO authenticated;

-- ---------------------------------------------------------------------------
-- cuenta
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS cuenta_insert_configurador ON cuenta;
DROP POLICY IF EXISTS cuenta_update_configurador ON cuenta;

CREATE POLICY cuenta_insert_configurador
    ON cuenta
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY cuenta_update_configurador
    ON cuenta
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON cuenta TO authenticated;

-- ---------------------------------------------------------------------------
-- usuario
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS usuario_insert_configurador ON usuario;
DROP POLICY IF EXISTS usuario_update_configurador ON usuario;

CREATE POLICY usuario_insert_configurador
    ON usuario
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY usuario_update_configurador
    ON usuario
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON usuario TO authenticated;

-- ---------------------------------------------------------------------------
-- bodega
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS bodega_insert_configurador ON bodega;
DROP POLICY IF EXISTS bodega_update_configurador ON bodega;

CREATE POLICY bodega_insert_configurador
    ON bodega
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY bodega_update_configurador
    ON bodega
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON bodega TO authenticated;

-- ---------------------------------------------------------------------------
-- asignacion_bodega
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS asignacion_bodega_insert_configurador ON asignacion_bodega;
DROP POLICY IF EXISTS asignacion_bodega_delete_configurador ON asignacion_bodega;

CREATE POLICY asignacion_bodega_insert_configurador
    ON asignacion_bodega
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY asignacion_bodega_delete_configurador
    ON asignacion_bodega
    FOR DELETE
    TO authenticated
    USING (auth_wms_es_configurador());

GRANT INSERT, DELETE ON asignacion_bodega TO authenticated;

-- ---------------------------------------------------------------------------
-- Plantilla: tablas sensibles futuras (POL-33 / inventario)
-- No crear tablas aquí; aplicar al exponer cada tabla vía PostgREST.
-- ---------------------------------------------------------------------------
-- REVOKE INSERT, UPDATE, DELETE ON warehouse_state FROM authenticated;
-- REVOKE INSERT, UPDATE, DELETE ON inventory_counter FROM authenticated;
-- GRANT SELECT ON warehouse_state TO authenticated;  -- solo si hay política SELECT explícita
-- Mutaciones vía backend (postgres) o funciones SECURITY DEFINER controladas.
