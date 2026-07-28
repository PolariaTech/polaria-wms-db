-- 056_cuenta_reporte_embed.sql — URL de reporte embebido por cuenta (Looker Studio)
--
-- Solo lectura/escritura vía service role (API Next). Sin PostgREST para authenticated.

CREATE TABLE IF NOT EXISTS cuenta_reporte_embed (
    codigo_cuenta varchar(32) PRIMARY KEY,
    embed_url text NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_cuenta_reporte_embed_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
        ON DELETE CASCADE,

    CONSTRAINT chk_cuenta_reporte_embed_url
        CHECK (char_length(btrim(embed_url)) > 0)
);

CREATE TRIGGER trg_cuenta_reporte_embed_updated_at
    BEFORE UPDATE ON cuenta_reporte_embed
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE cuenta_reporte_embed IS
    'URL de dashboard embebido (Looker Studio) por cuenta. Solo backend/service role.';

COMMENT ON COLUMN cuenta_reporte_embed.embed_url IS
    'URL de embed (p. ej. datastudio.google.com/embed/...). No exponer al cliente sin token.';

ALTER TABLE cuenta_reporte_embed ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON cuenta_reporte_embed FROM authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON cuenta_reporte_embed TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON cuenta_reporte_embed TO service_role;

-- Seed: cuenta JBR (bodega externa TCI)
INSERT INTO cuenta_reporte_embed (codigo_cuenta, embed_url, esta_activo)
VALUES (
    'JBR',
    'https://datastudio.google.com/embed/reporting/8319190c-7a5c-48b2-9b1d-84701d583dd9/page/RMmyF',
    true
)
ON CONFLICT (codigo_cuenta) DO UPDATE
SET
    embed_url = EXCLUDED.embed_url,
    esta_activo = EXCLUDED.esta_activo,
    updated_at = now();
