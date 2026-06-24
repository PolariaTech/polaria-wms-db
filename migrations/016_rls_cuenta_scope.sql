-- POL-2: políticas RLS de fase 1 con aislamiento por codigo_cuenta (helpers 015).
--
-- Validación de activación (no CHECK en tabla; la aplican los helpers y esta política):
--   - empresa: auth_wms_puede_ver_empresa exige empresa.esta_activa.
--   - cuenta:  auth_wms_puede_ver_cuenta exige cuenta.esta_activa y empresa.esta_activa.
--   - usuario: auth_wms_usuario_actual() exige usuario.esta_activo del caller;
--     usuario_select_scope_admin no filtra esta_activo del target (admins gestionan inactivos).
--
-- Patrón UPDATE/DELETE (futuro): Postgres exige que la fila sea visible vía FOR SELECT
-- antes de aplicar UPDATE o DELETE. Al agregar políticas UPDATE, definir:
--   CREATE POLICY ... FOR UPDATE TO authenticated
--       USING  (auth_wms_puede_ver_*(...))   -- visibilidad (equivalente SELECT)
--       WITH CHECK (auth_wms_puede_ver_*(...));  -- valores nuevos válidos
-- Sin política SELECT compatible, UPDATE/DELETE no afectará filas aunque exista USING en UPDATE.

-- Ejecución interna desde políticas RLS (015 revocó EXECUTE a authenticated).
GRANT EXECUTE ON FUNCTION auth_wms_usuario_actual() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_es_configurador() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_empresa(varchar) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_cuenta(varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- empresa
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS empresa_select_scope ON empresa;

CREATE POLICY empresa_select_scope
    ON empresa
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_empresa(codigo_empresa));

-- ---------------------------------------------------------------------------
-- cuenta
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS cuenta_select_scope ON cuenta;

CREATE POLICY cuenta_select_scope
    ON cuenta
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

-- ---------------------------------------------------------------------------
-- usuario
-- ---------------------------------------------------------------------------
-- usuario_select_own: sin cambios (cada usuario ve su propia fila).

-- usuario_select_scope_admin APLICA en fase 1:
--   - configurador (TI): ve todos los usuarios de la plataforma.
--   - administrador_cuenta sin codigo_cuenta: ve usuarios de su codigo_empresa
--     (todas las cuentas del tenant).
--   - administrador_cuenta con codigo_cuenta asignado: solo usuarios de esa cuenta.
-- Roles de bodega/operador no reciben SELECT extra (solo usuario_select_own).
DROP POLICY IF EXISTS usuario_select_scope_admin ON usuario;

CREATE POLICY usuario_select_scope_admin
    ON usuario
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_es_configurador()
        OR (
            (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'
            AND usuario.codigo_empresa = (auth_wms_usuario_actual()).codigo_empresa
            AND (
                (auth_wms_usuario_actual()).codigo_cuenta IS NULL
                OR usuario.codigo_cuenta = (auth_wms_usuario_actual()).codigo_cuenta
            )
        )
    );

-- TODO (fase posterior): usuario_select_scope_bodega cuando exista asignacion_bodega
-- para que jefe_bodega/administrador_bodega vean operarios de su bodega.
-- DROP POLICY IF EXISTS usuario_select_scope_bodega ON usuario;
-- CREATE POLICY usuario_select_scope_bodega ...

-- ===========================================================================
-- Pruebas manuales (comentadas). Requiere seed con dos cuentas en la misma empresa.
-- Simular sesión: SELECT set_config('request.jwt.claim.sub', '<uuid id_auth>', true);
-- En Supabase: autenticarse como cada usuario y ejecutar los SELECT.
-- ===========================================================================
--
-- -- Setup esperado: empresa ACME, cuentas ACME-01 y ACME-02, operador en ACME-01.
--
-- -- 1) Usuario de cuenta A no ve cuenta B (misma empresa)
-- SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
-- SELECT codigo_cuenta FROM cuenta ORDER BY codigo_cuenta;
-- -- Esperado: solo ACME-01 (operador_cuenta con codigo_cuenta = ACME-01)
--
-- -- 2) Configurador ve todas las cuentas activas
-- SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
-- SELECT codigo_cuenta, codigo_empresa FROM cuenta ORDER BY codigo_cuenta;
-- -- Esperado: ACME-01, ACME-02, ... (todas las activas)
--
-- -- 3) administrador_cuenta sin codigo_cuenta ve todas las cuentas de su empresa
-- SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
-- SELECT codigo_cuenta, codigo_empresa FROM cuenta ORDER BY codigo_cuenta;
-- -- Esperado: ACME-01 y ACME-02 (ambas de ACME), no cuentas de otras empresas
--
-- -- Verificación cruzada empresa (mismo alcance por helper)
-- SELECT codigo_empresa FROM empresa ORDER BY codigo_empresa;
