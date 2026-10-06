-- Estados OV tras foto QR de surtido: confirmada → alistamiento → alistada.
-- Aplica en public y en cada schema que tenga el enum estado_orden_venta.

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
        IF NOT EXISTS (
            SELECT 1
            FROM pg_enum e
            WHERE e.enumtypid = r.type_oid
              AND e.enumlabel = 'alistamiento'
        ) THEN
            EXECUTE format(
                'ALTER TYPE %I.estado_orden_venta ADD VALUE %L',
                r.schema_name,
                'alistamiento'
            );
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_enum e
            WHERE e.enumtypid = r.type_oid
              AND e.enumlabel = 'alistada'
        ) THEN
            EXECUTE format(
                'ALTER TYPE %I.estado_orden_venta ADD VALUE %L',
                r.schema_name,
                'alistada'
            );
        END IF;
    END LOOP;
END $$;

COMMENT ON TYPE public.estado_orden_venta IS
    'Estados OV: incluye alistamiento/alistada tras captura foto QR por OT.';
