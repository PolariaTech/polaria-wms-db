-- Bodega por defecto de la cuenta (debe pertenecer a la misma cuenta).

ALTER TABLE public.cuenta
    ADD COLUMN IF NOT EXISTS id_bodega_default uuid;

COMMENT ON COLUMN public.cuenta.id_bodega_default IS
    'Bodega operativa por defecto de la cuenta (FK lógica a bodega.id_bodega de la misma cuenta).';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_cuenta_bodega_default'
    ) THEN
        ALTER TABLE public.cuenta
            ADD CONSTRAINT fk_cuenta_bodega_default
            FOREIGN KEY (id_bodega_default)
            REFERENCES public.bodega (id_bodega)
            ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'id_bodega_default');
    END IF;
END $$;

-- FK por schema emp_* (si la columna ya existía sin constraint).
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
    LOOP
        IF EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = r.schema_name
              AND table_name = 'cuenta'
              AND column_name = 'id_bodega_default'
        ) AND NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            JOIN pg_namespace n ON n.oid = c.connamespace
            WHERE n.nspname = r.schema_name
              AND c.conname = 'fk_cuenta_bodega_default'
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.cuenta
                   ADD CONSTRAINT fk_cuenta_bodega_default
                   FOREIGN KEY (id_bodega_default)
                   REFERENCES %I.bodega (id_bodega)
                   ON DELETE SET NULL',
                r.schema_name,
                r.schema_name
            );
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
