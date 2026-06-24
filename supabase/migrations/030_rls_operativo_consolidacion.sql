-- POL-33 Fase 9: consolidación RLS operativo.
--
-- Las políticas SELECT/REVOKE/GRANT de tablas operativas (020–029) ya están aplicadas
-- en cada migración de dominio. Este archivo NO duplica políticas.
--
-- Añade helper combinado para filas C+B (cuenta + bodega) en migraciones futuras
-- o refactors de políticas sin alterar firmas de auth_wms_* existentes.

CREATE OR REPLACE FUNCTION auth_wms_puede_ver_fila_operativa(
    p_codigo_cuenta varchar,
    p_id_bodega uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        auth_wms_puede_ver_cuenta(p_codigo_cuenta)
        AND (
            p_id_bodega IS NULL
            OR auth_wms_puede_ver_bodega(p_id_bodega)
        )
$$;

COMMENT ON FUNCTION auth_wms_puede_ver_fila_operativa(varchar, uuid) IS
    'Alcance SELECT estándar tablas operativas C+B (POL-33). '
    'p_id_bodega NULL = solo cuenta (p. ej. auditoría a nivel tenant).';

REVOKE ALL ON FUNCTION auth_wms_puede_ver_fila_operativa(varchar, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_fila_operativa(varchar, uuid) TO authenticated;
