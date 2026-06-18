CREATE TABLE empresa (
    codigo_empresa varchar(32) PRIMARY KEY,
    razon_social varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_empresa_activa
    ON empresa (esta_activa)
    WHERE esta_activa;

CREATE TRIGGER trg_empresa_updated_at
    BEFORE UPDATE ON empresa
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE empresa ENABLE ROW LEVEL SECURITY;
