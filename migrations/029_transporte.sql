-- POL-33 Fase 8: transporte — viaje (TV), guía de envío y evidencias.
--
-- Rol transportista (wms_rol). Evidencias: URLs Cloudinary únicamente (sin blobs en BD).
-- Cierre de viaje, guías y evidencias: polaria-wms-api (NestJS, rol postgres).
-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE estado_viaje_transporte AS ENUM (
    'programado',
    'en_ruta',
    'entregado',
    'cancelado'
);

CREATE TYPE estado_guia_envio AS ENUM (
    'generada',
    'asignada',
    'en_transito',
    'entregada',
    'anulada'
);

CREATE TYPE tipo_evidencia_transporte AS ENUM (
    'foto',
    'firma'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION transporte_validar_guia_envio()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
    v_id_bodega uuid;
BEGIN
    SELECT vt.codigo_cuenta, vt.id_bodega
    INTO v_codigo_cuenta, v_id_bodega
    FROM viaje_transporte vt
    WHERE vt.id_viaje = NEW.id_viaje;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'viaje_transporte % no existe', NEW.id_viaje;
    END IF;

    NEW.codigo_cuenta := v_codigo_cuenta;

    IF NEW.id_orden_venta IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM orden_venta ov
            WHERE ov.id_orden_venta = NEW.id_orden_venta
              AND ov.codigo_cuenta = v_codigo_cuenta
              AND ov.id_bodega = v_id_bodega
        ) THEN
            RAISE EXCEPTION 'orden_venta % no coincide con cuenta/bodega del viaje', NEW.id_orden_venta;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION transporte_validar_evidencia()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM guia_envio g
        INNER JOIN viaje_transporte vt ON vt.id_viaje = g.id_viaje
        WHERE g.id_guia = NEW.id_guia
    ) THEN
        RAISE EXCEPTION 'guia_envio % no existe', NEW.id_guia;
    END IF;

    IF NEW.url_cloudinary IS NULL OR btrim(NEW.url_cloudinary) = '' THEN
        RAISE EXCEPTION 'url_cloudinary es obligatoria';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION transporte_evidencia_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'evidencia_transporte es append-only; no UPDATE ni DELETE';
END;
$$;

-- ---------------------------------------------------------------------------
-- viaje_transporte (TV) — alcance C+B (bodega origen)
-- ---------------------------------------------------------------------------
CREATE TABLE viaje_transporte (
    id_viaje uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    estado estado_viaje_transporte NOT NULL DEFAULT 'programado',
    id_transportista uuid,
    fecha_programada date NOT NULL DEFAULT CURRENT_DATE,
    fecha_salida timestamptz,
    fecha_cierre timestamptz,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_viaje_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_viaje_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_viaje_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_viaje_transportista
        FOREIGN KEY (id_transportista)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_viaje_cuenta ON viaje_transporte (codigo_cuenta);
CREATE INDEX ix_viaje_bodega ON viaje_transporte (id_bodega);
CREATE INDEX ix_viaje_bodega_estado ON viaje_transporte (id_bodega, estado);
CREATE INDEX ix_viaje_transportista ON viaje_transporte (id_transportista)
    WHERE id_transportista IS NOT NULL;
CREATE INDEX ix_viaje_cola ON viaje_transporte (id_bodega, estado, fecha_programada)
    WHERE estado IN ('programado', 'en_ruta');

CREATE TRIGGER trg_viaje_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON viaje_transporte
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_viaje_updated_at
    BEFORE UPDATE ON viaje_transporte
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE viaje_transporte IS
    'Viaje de transporte (TV). Cierre y estados solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- guia_envio
-- ---------------------------------------------------------------------------
CREATE TABLE guia_envio (
    id_guia uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_viaje uuid NOT NULL,
    id_orden_venta uuid,
    codigo varchar(32) NOT NULL,
    destino varchar(512) NOT NULL,
    estado estado_guia_envio NOT NULL DEFAULT 'generada',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_guia_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_guia_viaje
        FOREIGN KEY (id_viaje)
        REFERENCES viaje_transporte (id_viaje)
        ON DELETE CASCADE,

    CONSTRAINT fk_guia_orden_venta
        FOREIGN KEY (id_orden_venta)
        REFERENCES orden_venta (id_orden_venta)
        ON DELETE SET NULL
);

CREATE INDEX ix_guia_viaje ON guia_envio (id_viaje);
CREATE INDEX ix_guia_orden_venta ON guia_envio (id_orden_venta)
    WHERE id_orden_venta IS NOT NULL;
CREATE INDEX ix_guia_cuenta_estado ON guia_envio (codigo_cuenta, estado);
CREATE INDEX ix_guia_viaje_estado ON guia_envio (id_viaje, estado);

CREATE TRIGGER trg_guia_validar
    BEFORE INSERT OR UPDATE OF id_viaje, id_orden_venta ON guia_envio
    FOR EACH ROW
    EXECUTE FUNCTION transporte_validar_guia_envio();

CREATE TRIGGER trg_guia_updated_at
    BEFORE UPDATE ON guia_envio
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE guia_envio IS
    'Guía de envío asociada a un viaje y opcionalmente a una OV. POL-33.';

-- ---------------------------------------------------------------------------
-- evidencia_transporte — URLs Cloudinary (sin integración ni blobs en BD)
-- ---------------------------------------------------------------------------
CREATE TABLE evidencia_transporte (
    id_evidencia uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_guia uuid NOT NULL,
    tipo tipo_evidencia_transporte NOT NULL,
    url_cloudinary text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_evidencia_guia
        FOREIGN KEY (id_guia)
        REFERENCES guia_envio (id_guia)
        ON DELETE CASCADE
);

CREATE INDEX ix_evidencia_guia ON evidencia_transporte (id_guia);
CREATE INDEX ix_evidencia_tipo ON evidencia_transporte (id_guia, tipo);

CREATE TRIGGER trg_evidencia_validar
    BEFORE INSERT ON evidencia_transporte
    FOR EACH ROW
    EXECUTE FUNCTION transporte_validar_evidencia();

CREATE TRIGGER trg_evidencia_append_only
    BEFORE UPDATE OR DELETE ON evidencia_transporte
    FOR EACH ROW
    EXECUTE FUNCTION transporte_evidencia_append_only();

COMMENT ON TABLE evidencia_transporte IS
    'Evidencias de entrega (foto/firma). Solo URL Cloudinary; upload vía backend/app. POL-33.';

COMMENT ON COLUMN evidencia_transporte.url_cloudinary IS
    'URL pública o firmada de Cloudinary. No almacenar binarios en PostgreSQL.';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado; cierre de viaje y evidencias solo backend
-- ---------------------------------------------------------------------------
ALTER TABLE viaje_transporte ENABLE ROW LEVEL SECURITY;
ALTER TABLE guia_envio ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidencia_transporte ENABLE ROW LEVEL SECURITY;

CREATE POLICY viaje_transporte_select_scope
    ON viaje_transporte
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY guia_envio_select_scope
    ON guia_envio
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM viaje_transporte vt
            WHERE vt.id_viaje = guia_envio.id_viaje
              AND auth_wms_puede_ver_cuenta(vt.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(vt.id_bodega)
        )
    );

CREATE POLICY evidencia_transporte_select_scope
    ON evidencia_transporte
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM guia_envio g
            INNER JOIN viaje_transporte vt ON vt.id_viaje = g.id_viaje
            WHERE g.id_guia = evidencia_transporte.id_guia
              AND auth_wms_puede_ver_cuenta(vt.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(vt.id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON viaje_transporte FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON guia_envio FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON evidencia_transporte FROM authenticated;

GRANT SELECT ON viaje_transporte TO authenticated;
GRANT SELECT ON guia_envio TO authenticated;
GRANT SELECT ON evidencia_transporte TO authenticated;
