-- 084_usuario_reporte_embed.sql
-- Permisos de reportes embebidos por usuario + reporte_id obligatorio en cuenta_reporte_embed.

CREATE TABLE IF NOT EXISTS public.usuario_reporte_embed (
    id_usuario_reporte_embed uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario uuid NOT NULL,
    id_cuenta_reporte_embed uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_usuario_reporte_embed_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES public.usuario (id_usuario)
        ON DELETE CASCADE,

    CONSTRAINT fk_usuario_reporte_embed_reporte
        FOREIGN KEY (id_cuenta_reporte_embed)
        REFERENCES public.cuenta_reporte_embed (id_cuenta_reporte_embed)
        ON DELETE CASCADE,

    CONSTRAINT uq_usuario_reporte_embed UNIQUE (id_usuario, id_cuenta_reporte_embed)
);

CREATE INDEX IF NOT EXISTS idx_usuario_reporte_embed_usuario
    ON public.usuario_reporte_embed (id_usuario);

CREATE INDEX IF NOT EXISTS idx_usuario_reporte_embed_reporte
    ON public.usuario_reporte_embed (id_cuenta_reporte_embed);

DROP TRIGGER IF EXISTS trg_usuario_reporte_embed_updated_at
    ON public.usuario_reporte_embed;

CREATE TRIGGER trg_usuario_reporte_embed_updated_at
    BEFORE UPDATE ON public.usuario_reporte_embed
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.usuario_reporte_embed IS
    'Grant de acceso a un reporte embebido de la cuenta. Solo backend/service role.';

COMMENT ON COLUMN public.usuario_reporte_embed.id_usuario IS
    'Usuario al que se le asigna el reporte (URL embebida de la cuenta).';

COMMENT ON COLUMN public.usuario_reporte_embed.id_cuenta_reporte_embed IS
    'Reporte de cuenta_reporte_embed al que el usuario puede entrar.';

ALTER TABLE public.usuario_reporte_embed ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.usuario_reporte_embed FROM authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.usuario_reporte_embed TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.usuario_reporte_embed TO service_role;

INSERT INTO public.wms_tenant_tables (table_name, clone_order)
SELECT 'usuario_reporte_embed',
       COALESCE((SELECT max(clone_order) + 10 FROM public.wms_tenant_tables), 390)
WHERE EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wms_tenant_tables'
)
AND NOT EXISTS (
    SELECT 1 FROM public.wms_tenant_tables WHERE table_name = 'usuario_reporte_embed'
);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_table_to_tenants'
    ) THEN
        PERFORM public.wms_sync_table_to_tenants('usuario_reporte_embed');
    END IF;
END $$;

-- Backfill reporte_id nulos (UUID Looker en la URL, o uno nuevo) y lo deja NOT NULL.
DO $$
DECLARE
    r_schema text;
    r record;
    extracted uuid;
BEGIN
    FOR r_schema IN
        SELECT nspname
        FROM pg_namespace
        WHERE nspname = 'public'
           OR nspname LIKE 'emp\_%'
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = r_schema
              AND table_name = 'cuenta_reporte_embed'
              AND column_name = 'reporte_id'
        ) THEN
            CONTINUE;
        END IF;

        FOR r IN EXECUTE format(
            'SELECT id_cuenta_reporte_embed, embed_url
             FROM %I.cuenta_reporte_embed
             WHERE reporte_id IS NULL',
            r_schema
        )
        LOOP
            extracted := NULL;
            BEGIN
                extracted := (
                    regexp_match(
                        r.embed_url,
                        '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
                    )
                )[1]::uuid;
            EXCEPTION
                WHEN others THEN
                    extracted := NULL;
            END;

            BEGIN
                EXECUTE format(
                    'UPDATE %I.cuenta_reporte_embed
                     SET reporte_id = $1, updated_at = now()
                     WHERE id_cuenta_reporte_embed = $2',
                    r_schema
                )
                USING COALESCE(extracted, gen_random_uuid()), r.id_cuenta_reporte_embed;
            EXCEPTION
                WHEN unique_violation THEN
                    EXECUTE format(
                        'UPDATE %I.cuenta_reporte_embed
                         SET reporte_id = $1, updated_at = now()
                         WHERE id_cuenta_reporte_embed = $2',
                        r_schema
                    )
                    USING gen_random_uuid(), r.id_cuenta_reporte_embed;
            END;
        END LOOP;

        EXECUTE format(
            'ALTER TABLE %I.cuenta_reporte_embed ALTER COLUMN reporte_id SET NOT NULL',
            r_schema
        );
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
