-- POL-33 Fase 7a: orden_trabajo (OT) — procesamiento en bodega.
--
-- Roles operario / procesador / jefe_bodega (wms_rol). Cola operativa: POL-42 futuro.
-- Mutaciones y cambios de estado: polaria-wms-api (NestJS, rol postgres).
-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE estado_orden_trabajo AS ENUM (
    'planificada',
    'en_proceso',
    'pausada',
    'completada',
    'cancelada'
);

CREATE TYPE tipo_orden_trabajo AS ENUM (
    'picking',
    'merma',
    'transformacion',
    'reabasto',
    'conteo',
    'otro'
);

CREATE TYPE tipo_linea_ot AS ENUM (
    'entrada',
    'salida',
    'subproducto'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION procesamiento_validar_linea_ot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
    v_id_bodega uuid;
BEGIN
    SELECT ot.codigo_cuenta, ot.id_bodega
    INTO v_codigo_cuenta, v_id_bodega
    FROM orden_trabajo ot
    WHERE ot.id_orden_trabajo = NEW.id_orden_trabajo;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'orden_trabajo % no existe', NEW.id_orden_trabajo;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM producto p
        WHERE p.id_producto = NEW.id_producto
          AND p.codigo_cuenta = v_codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'producto % no pertenece a la cuenta del OT', NEW.id_producto;
    END IF;

    IF NEW.id_ubicacion IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ubicacion u
            WHERE u.id_ubicacion = NEW.id_ubicacion
              AND u.id_bodega = v_id_bodega
              AND u.codigo_cuenta = v_codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'ubicacion % no pertenece a la bodega del OT', NEW.id_ubicacion;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- orden_trabajo (OT) — alcance C+B
-- ---------------------------------------------------------------------------
CREATE TABLE orden_trabajo (
    id_orden_trabajo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    estado estado_orden_trabajo NOT NULL DEFAULT 'planificada',
    tipo tipo_orden_trabajo NOT NULL DEFAULT 'otro',
    id_asignado uuid,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_orden_trabajo_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_orden_trabajo_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_orden_trabajo_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_orden_trabajo_asignado
        FOREIGN KEY (id_asignado)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_orden_trabajo_cuenta ON orden_trabajo (codigo_cuenta);
CREATE INDEX ix_orden_trabajo_bodega ON orden_trabajo (id_bodega);
CREATE INDEX ix_orden_trabajo_bodega_estado ON orden_trabajo (id_bodega, estado);
CREATE INDEX ix_orden_trabajo_cola ON orden_trabajo (id_bodega, estado, tipo, created_at)
    WHERE estado IN ('planificada', 'en_proceso', 'pausada');
CREATE INDEX ix_orden_trabajo_asignado ON orden_trabajo (id_asignado)
    WHERE id_asignado IS NOT NULL;

CREATE TRIGGER trg_orden_trabajo_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON orden_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_orden_trabajo_updated_at
    BEFORE UPDATE ON orden_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE orden_trabajo IS
    'Orden de trabajo (OT). Cola operativa POL-42. Mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- orden_trabajo_linea
-- ---------------------------------------------------------------------------
CREATE TABLE orden_trabajo_linea (
    id_linea_orden_trabajo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_trabajo uuid NOT NULL,
    id_producto uuid NOT NULL,
    id_ubicacion uuid,
    tipo_linea tipo_linea_ot NOT NULL,
    cantidad numeric(18, 4) NOT NULL,

    CONSTRAINT chk_ot_linea_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT fk_ot_linea_orden
        FOREIGN KEY (id_orden_trabajo)
        REFERENCES orden_trabajo (id_orden_trabajo)
        ON DELETE CASCADE,

    CONSTRAINT fk_ot_linea_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_ot_linea_ubicacion
        FOREIGN KEY (id_ubicacion)
        REFERENCES ubicacion (id_ubicacion)
);

CREATE INDEX ix_ot_linea_orden ON orden_trabajo_linea (id_orden_trabajo);
CREATE INDEX ix_ot_linea_producto ON orden_trabajo_linea (id_producto);
CREATE INDEX ix_ot_linea_ubicacion ON orden_trabajo_linea (id_ubicacion)
    WHERE id_ubicacion IS NOT NULL;

CREATE TRIGGER trg_ot_linea_validar
    BEFORE INSERT OR UPDATE OF id_orden_trabajo, id_producto, id_ubicacion
        ON orden_trabajo_linea
    FOR EACH ROW
    EXECUTE FUNCTION procesamiento_validar_linea_ot();

COMMENT ON TABLE orden_trabajo_linea IS
    'Líneas de OT (entrada/salida/subproducto). Mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado; cambios de estado solo backend
-- ---------------------------------------------------------------------------
ALTER TABLE orden_trabajo ENABLE ROW LEVEL SECURITY;
ALTER TABLE orden_trabajo_linea ENABLE ROW LEVEL SECURITY;

CREATE POLICY orden_trabajo_select_scope
    ON orden_trabajo
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY orden_trabajo_linea_select_scope
    ON orden_trabajo_linea
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM orden_trabajo ot
            WHERE ot.id_orden_trabajo = orden_trabajo_linea.id_orden_trabajo
              AND auth_wms_puede_ver_cuenta(ot.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ot.id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON orden_trabajo FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON orden_trabajo_linea FROM authenticated;

GRANT SELECT ON orden_trabajo TO authenticated;
GRANT SELECT ON orden_trabajo_linea TO authenticated;
