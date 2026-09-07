-- INSERT de precio vigente: quien puede ver la cuenta (incluye operador_cuenta).
-- Antes solo admin/configurador → operadores legacy en public fallaban al guardar equivalencias.

DROP POLICY IF EXISTS precio_producto_insert_cuenta ON public.precio_producto;

CREATE POLICY precio_producto_insert_cuenta
    ON public.precio_producto
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_puede_ver_cuenta(codigo_cuenta));

GRANT INSERT ON public.precio_producto TO authenticated;
