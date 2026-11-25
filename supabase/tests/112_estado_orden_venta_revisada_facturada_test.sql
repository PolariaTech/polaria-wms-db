-- Prueba de la migración 112: public.estado_orden_venta incluye revisada y facturada.
-- Corre en BEGIN/ROLLBACK dentro del humo SQL de CI.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'estado_orden_venta' AND e.enumlabel = 'revisada'
  ) THEN
    RAISE EXCEPTION 'FALLA 1: falta el valor revisada en public.estado_orden_venta';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'estado_orden_venta' AND e.enumlabel = 'facturada'
  ) THEN
    RAISE EXCEPTION 'FALLA 2: falta el valor facturada en public.estado_orden_venta';
  END IF;

  RAISE NOTICE 'OK: 112_estado_orden_venta_revisada_facturada, 2 afirmaciones';
END $$;

ROLLBACK;
