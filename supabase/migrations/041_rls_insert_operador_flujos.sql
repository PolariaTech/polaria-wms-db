-- 041 RLS INSERT — flujos operador (P0)
--
-- Habilita INSERT vía PostgREST (rol authenticated) en tablas que el web escribe hoy
-- con supabase-js, sin abrir UPDATE/DELETE ni orden_venta (prompt 5).
--
-- Criterio: mismos helpers auth_wms_* que SELECT (015–017, 030).
-- solicitud_integracion: alcance cuenta; solo roles comerciales de la cuenta.
-- solicitud_procesamiento: alcance C+B (cuenta + bodega visible al caller).

-- ---------------------------------------------------------------------------
-- solicitud_integracion
-- El frontend crea solicitudes de integración Fridem (040) desde operadores de
-- cuenta. SELECT ya usa auth_wms_puede_ver_cuenta; INSERT acota a
-- administrador_cuenta y operador_cuenta del mismo codigo_cuenta (vía helper),
-- excluyendo roles bodega que no originan este flujo comercial.
-- UPDATE/DELETE permanecen en backend / configurador futuro.
-- ---------------------------------------------------------------------------
CREATE POLICY solicitud_integracion_insert_cuenta
    ON solicitud_integracion
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    );

GRANT INSERT ON solicitud_integracion TO authenticated;

-- ---------------------------------------------------------------------------
-- solicitud_procesamiento
-- El web crea borradores de procesamiento (035) desde roles cuenta o bodega.
-- WITH CHECK replica el SELECT existente:
--   auth_wms_puede_ver_cuenta(codigo_cuenta)
--   AND auth_wms_puede_ver_bodega(id_bodega)
-- Roles cuenta: su tenant; roles bodega: solo bodegas en asignacion_bodega.
-- UPDATE/cierre y registro_merma siguen vía backend hasta política dedicada.
-- ---------------------------------------------------------------------------
CREATE POLICY solicitud_procesamiento_insert_scope
    ON solicitud_procesamiento
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

GRANT INSERT ON solicitud_procesamiento TO authenticated;

-- ---------------------------------------------------------------------------
-- Verificación post-migración (falla el deploy si faltan políticas)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'solicitud_integracion'
          AND policyname = 'solicitud_integracion_insert_cuenta'
          AND cmd = 'INSERT'
    ) THEN
        RAISE EXCEPTION 'Falta política solicitud_integracion_insert_cuenta';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'solicitud_procesamiento'
          AND policyname = 'solicitud_procesamiento_insert_scope'
          AND cmd = 'INSERT'
    ) THEN
        RAISE EXCEPTION 'Falta política solicitud_procesamiento_insert_scope';
    END IF;

    RAISE NOTICE '041: políticas INSERT solicitud_integracion y solicitud_procesamiento OK';
END;
$$;
