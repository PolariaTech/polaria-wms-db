-- 080 RLS UPDATE/DELETE — editar OV desde el operador (P1 ventas)
--
-- Crear pedido ya tenía INSERT (042). Editar hace UPDATE de cabecera,
-- DELETE de líneas y INSERT de líneas nuevas. Sin GRANT UPDATE Postgres
-- responde "permission denied for table orden_venta".
-- Solo estados editables: borrador, confirmada, en_preparacion.
-- No abre DELETE de la cabecera ni cambio a despachada/cerrada/cancelada.

DROP POLICY IF EXISTS orden_venta_update_editable ON public.orden_venta;
CREATE POLICY orden_venta_update_editable
    ON public.orden_venta
    FOR UPDATE
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
        AND estado IN ('borrador', 'confirmada', 'en_preparacion')
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    )
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
        AND estado IN ('borrador', 'confirmada', 'en_preparacion')
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    );

DROP POLICY IF EXISTS orden_venta_linea_delete_editable ON public.orden_venta_linea;
CREATE POLICY orden_venta_linea_delete_editable
    ON public.orden_venta_linea
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.orden_venta ov
            WHERE ov.id_orden_venta = orden_venta_linea.id_orden_venta
              AND ov.estado IN ('borrador', 'confirmada', 'en_preparacion')
              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ov.id_bodega)
              AND (auth_wms_usuario_actual()).id_rol IN (
                  'administrador_cuenta',
                  'operador_cuenta'
              )
        )
    );

DROP POLICY IF EXISTS orden_venta_linea_insert_editable ON public.orden_venta_linea;
CREATE POLICY orden_venta_linea_insert_editable
    ON public.orden_venta_linea
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.orden_venta ov
            WHERE ov.id_orden_venta = orden_venta_linea.id_orden_venta
              AND ov.estado IN ('borrador', 'confirmada', 'en_preparacion')
              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ov.id_bodega)
              AND (auth_wms_usuario_actual()).id_rol IN (
                  'administrador_cuenta',
                  'operador_cuenta'
              )
        )
    );

GRANT UPDATE ON public.orden_venta TO authenticated;
GRANT UPDATE, DELETE ON public.orden_venta_linea TO authenticated;

DO $$
DECLARE
    sch text;
BEGIN
    FOR sch IN
        SELECT nspname
        FROM pg_namespace
        WHERE nspname LIKE 'emp_%'
        ORDER BY nspname
    LOOP
        EXECUTE format(
            'GRANT UPDATE ON TABLE %I.orden_venta TO authenticated',
            sch
        );
        EXECUTE format(
            'GRANT UPDATE, DELETE ON TABLE %I.orden_venta_linea TO authenticated',
            sch
        );
    END LOOP;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'orden_venta'
          AND policyname = 'orden_venta_update_editable'
          AND cmd = 'UPDATE'
    ) THEN
        RAISE EXCEPTION 'Falta política orden_venta_update_editable';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'orden_venta_linea'
          AND policyname = 'orden_venta_linea_delete_editable'
          AND cmd = 'DELETE'
    ) THEN
        RAISE EXCEPTION 'Falta política orden_venta_linea_delete_editable';
    END IF;

    IF NOT has_table_privilege('authenticated', 'public.orden_venta', 'UPDATE') THEN
        RAISE EXCEPTION 'authenticated sigue sin UPDATE en public.orden_venta';
    END IF;

    RAISE NOTICE '080: UPDATE/DELETE editable de orden_venta OK';
END;
$$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
