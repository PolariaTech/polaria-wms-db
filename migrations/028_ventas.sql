-- POL-33 Fase 7b: orden_venta (OV) — despacho / ventas.
--
-- Mutaciones y cambios de estado: polaria-wms-api (NestJS, rol postgres).
-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega origen.
-- Índices de cola operativa preparados para POL-42 futuro.

-- ---------------------------------------------------------------------------
-- Enum
-- ---------------------------------------------------------------------------
CREATE TYPE estado_orden_venta AS ENUM (
    'borrador',
    'confirmada',
    'en_preparacion',
    'parcialmente_despachada',
    'despachada',
    'cerrada',
    'cancelada'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ventas_validar_orden_venta_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM cliente c
        WHERE c.id_cliente = NEW.id_cliente
          AND c.codigo_cuenta = NEW.codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'cliente % no pertenece a la cuenta %', NEW.id_cliente, NEW.codigo_cuenta;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ventas_validar_linea_ov()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
BEGIN
    SELECT ov.codigo_cuenta
    INTO v_codigo_cuenta
    FROM orden_venta ov
    WHERE ov.id_orden_venta = NEW.id_orden_venta;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'orden_venta % no existe', NEW.id_orden_venta;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM producto p
        WHERE p.id_producto = NEW.id_producto
          AND p.codigo_cuenta = v_codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'producto % no pertenece a la cuenta de la OV', NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- orden_venta (OV) — alcance C+B (bodega origen / despacho)
-- ---------------------------------------------------------------------------
CREATE TABLE orden_venta (
    id_orden_venta uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_cliente uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    estado estado_orden_venta NOT NULL DEFAULT 'borrador',
    fecha_pedido date NOT NULL DEFAULT CURRENT_DATE,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_orden_venta_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_orden_venta_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_orden_venta_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_orden_venta_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
);

CREATE INDEX ix_orden_venta_cuenta ON orden_venta (codigo_cuenta);
CREATE INDEX ix_orden_venta_bodega ON orden_venta (id_bodega);
CREATE INDEX ix_orden_venta_cliente ON orden_venta (id_cliente);
CREATE INDEX ix_orden_venta_bodega_estado ON orden_venta (id_bodega, estado);
CREATE INDEX ix_orden_venta_cola ON orden_venta (id_bodega, estado, created_at)
    WHERE estado IN ('confirmada', 'en_preparacion', 'parcialmente_despachada');
CREATE INDEX ix_orden_venta_cuenta_estado ON orden_venta (codigo_cuenta, estado);

CREATE TRIGGER trg_orden_venta_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON orden_venta
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_orden_venta_validar_refs
    BEFORE INSERT OR UPDATE OF codigo_cuenta, id_cliente ON orden_venta
    FOR EACH ROW
    EXECUTE FUNCTION ventas_validar_orden_venta_referencias();

CREATE TRIGGER trg_orden_venta_updated_at
    BEFORE UPDATE ON orden_venta
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE orden_venta IS
    'Orden de venta (OV). Bodega origen = despacho. Cola POL-42. Mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- orden_venta_linea
-- ---------------------------------------------------------------------------
CREATE TABLE orden_venta_linea (
    id_linea_orden_venta uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_venta uuid NOT NULL,
    id_producto uuid NOT NULL,
    cantidad_pedida numeric(18, 4) NOT NULL,
    cantidad_despachada numeric(18, 4) NOT NULL DEFAULT 0,

    CONSTRAINT chk_ov_linea_pedida_positiva CHECK (cantidad_pedida > 0),
    CONSTRAINT chk_ov_linea_despachada_no_negativa CHECK (cantidad_despachada >= 0),
    CONSTRAINT chk_ov_linea_despachada_max CHECK (cantidad_despachada <= cantidad_pedida),

    CONSTRAINT fk_ov_linea_orden
        FOREIGN KEY (id_orden_venta)
        REFERENCES orden_venta (id_orden_venta)
        ON DELETE CASCADE,

    CONSTRAINT fk_ov_linea_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
);

CREATE INDEX ix_ov_linea_orden ON orden_venta_linea (id_orden_venta);
CREATE INDEX ix_ov_linea_producto ON orden_venta_linea (id_producto);

CREATE TRIGGER trg_ov_linea_validar
    BEFORE INSERT OR UPDATE OF id_orden_venta, id_producto ON orden_venta_linea
    FOR EACH ROW
    EXECUTE FUNCTION ventas_validar_linea_ov();

COMMENT ON TABLE orden_venta_linea IS
    'Líneas de OV. Mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado; cambios de estado solo backend
-- ---------------------------------------------------------------------------
ALTER TABLE orden_venta ENABLE ROW LEVEL SECURITY;
ALTER TABLE orden_venta_linea ENABLE ROW LEVEL SECURITY;

CREATE POLICY orden_venta_select_scope
    ON orden_venta
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY orden_venta_linea_select_scope
    ON orden_venta_linea
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM orden_venta ov
            WHERE ov.id_orden_venta = orden_venta_linea.id_orden_venta
              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ov.id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON orden_venta FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON orden_venta_linea FROM authenticated;

GRANT SELECT ON orden_venta TO authenticated;
GRANT SELECT ON orden_venta_linea TO authenticated;
