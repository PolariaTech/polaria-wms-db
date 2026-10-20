-- Soft-delete OV: permitir pasar a estado `cancelada` (UI: «Borrar»).
-- USING sigue exigiendo OV editable; WITH CHECK admite el destino cancelada.

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
            'en_preparacion',
            'cancelada'
        )
        AND (auth_wms_usuario_actual()).id_rol IN (
            'administrador_cuenta',
            'operador_cuenta'
        )
    );

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
