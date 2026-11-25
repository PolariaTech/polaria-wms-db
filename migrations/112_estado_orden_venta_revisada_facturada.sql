-- Estados OV post-foto QR / Cypher (REQ-058):
-- confirmada → alistamiento → alistada → revisada → despachada → facturada.
--
-- El tipo `estado_orden_venta` vive en **public**. `template_wms` y todos los
-- `emp_*` (p. ej. emp_jbr_cygnus_y9ihz) tipan `orden_venta.estado` con ese
-- mismo enum de public (LIKE al clonar). No hay que alterar un schema tenant
-- suelto: al agregar el valor en public queda disponible para todos.
--
-- Igual se itera cualquier schema que tenga una copia local del tipo, por
-- defensiva (mismo patrón que 089 / 094).

DO $$
DECLARE
    r record;
    v_label text;
BEGIN
    FOREACH v_label IN ARRAY ARRAY['revisada', 'facturada']
    LOOP
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
                  AND e.enumlabel = v_label
            ) THEN
                EXECUTE format(
                    'ALTER TYPE %I.estado_orden_venta ADD VALUE %L',
                    r.schema_name,
                    v_label
                );
            END IF;
        END LOOP;
    END LOOP;
END $$;

COMMENT ON TYPE public.estado_orden_venta IS
    'Estados OV: por_confirmar → confirmada → alistamiento → alistada → revisada → despachada → facturada (más legados).';

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
