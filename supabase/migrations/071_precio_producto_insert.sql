-- Permite registrar un nuevo precio vigente desde el admin/operador
-- (historial por fecha_aplicacion). Alcance = misma cuenta que SELECT.

DROP POLICY IF EXISTS precio_producto_insert_cuenta ON public.precio_producto;

CREATE POLICY precio_producto_insert_cuenta
    ON public.precio_producto
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_puede_ver_cuenta(codigo_cuenta));

GRANT INSERT ON public.precio_producto TO authenticated;
