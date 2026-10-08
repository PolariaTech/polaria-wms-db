-- Renombra estado OV `borrador` → `por_confirmar` (valor en BD = etiqueta de negocio).
-- Aplica al enum en public y en cada schema emp_* que lo tenga.
-- Actualiza DEFAULT y políticas RLS que referencian el valor viejo.

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name, t.oid AS type_oid
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE t.typname = 'estado_orden_venta'
        ORDER BY n.nspname
    LOOP
        IF EXISTS (
            SELECT 1
            FROM pg_enum e
            WHERE e.enumtypid = r.type_oid
              AND e.enumlabel = 'borrador'
        ) AND NOT EXISTS (
            SELECT 1
            FROM pg_enum e
            WHERE e.enumtypid = r.type_oid
              AND e.enumlabel = 'por_confirmar'
        ) THEN
            EXECUTE format(
                'ALTER TYPE %I.estado_orden_venta RENAME VALUE %L TO %L',
                r.schema_name,
                'borrador',
                'por_confirmar'
            );
        END IF;

        IF to_regclass(format('%I.orden_venta', r.schema_name)) IS NOT NULL THEN
            EXECUTE format(
                'ALTER TABLE %I.orden_venta ALTER COLUMN estado SET DEFAULT %L',
                r.schema_name,
                'por_confirmar'
            );
        END IF;
    END LOOP;
END $$;

-- Políticas public: recrear con por_confirmar (y estados editables ya usados).
DROP POLICY IF EXISTS orden_venta_insert_cuenta ON public.orden_venta;
CREATE POLICY orden_venta_insert_cuenta
    ON public.orden_venta
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
        AND estado = 'por_confirmar'
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    );

DROP POLICY IF EXISTS orden_venta_linea_insert_borrador ON public.orden_venta_linea;
CREATE POLICY orden_venta_linea_insert_por_confirmar
    ON public.orden_venta_linea
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.orden_venta ov
            WHERE ov.id_orden_venta = orden_venta_linea.id_orden_venta
              AND ov.estado = 'por_confirmar'
              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ov.id_bodega)
              AND (auth_wms_usuario_actual()).id_rol IN (
                  'administrador_cuenta',
                  'operador_cuenta'
              )
        )
    );

DROP POLICY IF EXISTS orden_venta_update_editable ON public.orden_venta;
CREATE POLICY orden_venta_update_editable
    ON public.orden_venta
    FOR UPDATE
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
        AND estado IN (
            'por_confirmar',
            'confirmada',
            'alistamiento',
            'alistada',
            'en_preparacion'
        )
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    )
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
        AND estado IN (
            'por_confirmar',
            'confirmada',
            'alistamiento',
            'alistada',
            'en_preparacion'
        )
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
              AND ov.estado IN (
                  'por_confirmar',
                  'confirmada',
                  'alistamiento',
                  'alistada',
                  'en_preparacion'
              )
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
              AND ov.estado IN (
                  'por_confirmar',
                  'confirmada',
                  'alistamiento',
                  'alistada',
                  'en_preparacion'
              )
              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ov.id_bodega)
              AND (auth_wms_usuario_actual()).id_rol IN (
                  'administrador_cuenta',
                  'operador_cuenta'
              )
        )
    );

COMMENT ON TYPE public.estado_orden_venta IS
    'Estados OV de negocio: por_confirmar, confirmada, alistamiento, alistada (Alistado). Valores legados pueden existir en el enum.';

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
