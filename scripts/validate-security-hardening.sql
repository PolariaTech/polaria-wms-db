-- validate-security-hardening.sql — validación postura de seguridad V2
--
-- Prerrequisitos: migraciones 001–053 aplicadas.
-- Ejecutar como postgres en Supabase SQL Editor.

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
    v_rls_off integer;
    v_ws_insert boolean;
    v_audit_mutate boolean;
    v_security_event_rls boolean;
BEGIN
    SELECT COUNT(*)::integer
    INTO v_rls_off
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE (
            (n.nspname = 'public' AND c.relname IN (
                'empresa', 'cuenta', 'bodega', 'warehouse_state',
                'movimiento_inventario', 'auditoria_operacion'
            ))
            OR (n.nspname = 'mateo_support' AND c.relname IN (
                'widget_conversacion', 'widget_mensaje'
            ))
          )
      AND c.relkind = 'r'
      AND NOT c.relrowsecurity;

    PERFORM test_rls.assert_true(
        'RLS habilitado en tablas críticas',
        v_rls_off = 0
    );

    SELECT has_table_privilege('authenticated', 'public.warehouse_state', 'INSERT')
    INTO v_ws_insert;

    PERFORM test_rls.assert_true(
        'authenticated sin INSERT en warehouse_state',
        NOT v_ws_insert
    );

    SELECT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_auditoria_append_only'
    )
    INTO v_audit_mutate;

    PERFORM test_rls.assert_true(
        'trigger append-only en auditoria_operacion',
        v_audit_mutate
    );

    SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'security_event'
          AND c.relrowsecurity
    )
    INTO v_security_event_rls;

    PERFORM test_rls.assert_true(
        'security_event con RLS (migración 053)',
        v_security_event_rls
    );

    RAISE NOTICE '=== validate-security-hardening: validación completada ===';
END;
$$;
