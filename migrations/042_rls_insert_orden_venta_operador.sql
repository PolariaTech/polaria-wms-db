-- 042 RLS INSERT — orden_venta borrador (P1 ventas operador)
--
-- Habilita creación mínima de OV desde polaria-wms-web (operador_cuenta /
-- administrador_cuenta) vía PostgREST. Solo INSERT en borrador; UPDATE/estado
-- sigue en polaria-wms-api.

CREATE POLICY orden_venta_insert_cuenta
    ON orden_venta
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
        AND estado = 'borrador'
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    );

CREATE POLICY orden_venta_linea_insert_borrador
    ON orden_venta_linea
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM orden_venta ov
            WHERE ov.id_orden_venta = orden_venta_linea.id_orden_venta
              AND ov.estado = 'borrador'
              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ov.id_bodega)
              AND (auth_wms_usuario_actual()).id_rol IN (
                  'administrador_cuenta',
                  'operador_cuenta'
              )
        )
    );

GRANT INSERT ON orden_venta TO authenticated;
GRANT INSERT ON orden_venta_linea TO authenticated;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'orden_venta'
          AND policyname = 'orden_venta_insert_cuenta'
          AND cmd = 'INSERT'
    ) THEN
        RAISE EXCEPTION 'Falta política orden_venta_insert_cuenta';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'orden_venta_linea'
          AND policyname = 'orden_venta_linea_insert_borrador'
          AND cmd = 'INSERT'
    ) THEN
        RAISE EXCEPTION 'Falta política orden_venta_linea_insert_borrador';
    END IF;

    RAISE NOTICE '042: políticas INSERT orden_venta y orden_venta_linea OK';
END;
$$;
