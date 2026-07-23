-- validate-mapa-pol141.sql — POL-141 coherencia estado_slot vs warehouse_state
--
-- Prerrequisitos: validate-phase1.sql, validate-rls-operativo.sql (seed operativo)
--
-- Ejecutar en Supabase SQL Editor o: psql -f scripts/validate-mapa-pol141.sql

CREATE SCHEMA IF NOT EXISTS test_rls;

CREATE OR REPLACE FUNCTION test_rls.assert_true(p_label text, p_ok boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT p_ok THEN
        RAISE EXCEPTION 'FALLÓ: %', p_label;
    END IF;
    RAISE NOTICE 'OK: %', p_label;
END;
$$;

DO $$
DECLARE
    v_incoherentes integer;
BEGIN
    SELECT COUNT(*)::integer
    INTO v_incoherentes
    FROM ubicacion u
    WHERE EXISTS (
        SELECT 1
        FROM warehouse_state ws
        WHERE ws.id_ubicacion = u.id_ubicacion
          AND ws.cantidad > 0
    ) <> (u.estado_slot = 'ocupado');

    PERFORM test_rls.assert_true(
        'estado_slot coherente con stock activo en warehouse_state',
        v_incoherentes = 0
    );

    RAISE NOTICE '=== validate-mapa-pol141: validación completada ===';
END;
$$;
