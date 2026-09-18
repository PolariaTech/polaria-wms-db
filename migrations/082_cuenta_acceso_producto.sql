-- Acceso de producto por cuenta: WMS, Mateo IA, o ambos.
-- Default ambos = true para no cambiar el comportamiento de cuentas existentes.

ALTER TABLE public.cuenta
    ADD COLUMN IF NOT EXISTS acceso_wms boolean NOT NULL DEFAULT true;

ALTER TABLE public.cuenta
    ADD COLUMN IF NOT EXISTS acceso_mateo boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.cuenta.acceso_wms IS
    'Si es true, los usuarios de la cuenta pueden operar Polaria WMS.';

COMMENT ON COLUMN public.cuenta.acceso_mateo IS
    'Si es true, los usuarios de la cuenta pueden entrar a Mateo IA (botón topbar o redirect).';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_cuenta_acceso_producto'
    ) THEN
        ALTER TABLE public.cuenta
            ADD CONSTRAINT ck_cuenta_acceso_producto
            CHECK (acceso_wms OR acceso_mateo);
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
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'acceso_wms');
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'acceso_mateo');
    END IF;
END $$;

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
              AND column_name = 'acceso_wms'
        ) AND NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            JOIN pg_namespace n ON n.oid = c.connamespace
            WHERE n.nspname = r.schema_name
              AND c.conname = 'ck_cuenta_acceso_producto'
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.cuenta
                   ADD CONSTRAINT ck_cuenta_acceso_producto
                   CHECK (acceso_wms OR acceso_mateo)',
                r.schema_name
            );
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
