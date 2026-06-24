-- POL-33 Fase 3: compras — solicitud de compra (SOL) y orden de compra (OC).
--
-- Esta estructura desbloquea POL-5 (ingreso / recepción contra OC).
-- Sin triggers de inventario (warehouse_state en migración posterior).
--
-- Mutaciones (cabeceras, líneas, cambios de estado): polaria-wms-api (NestJS, rol postgres).
-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega.
-- Ver docs/modelo-operativo-v2.md y docs/rls-politicas.md.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE estado_solicitud_compra AS ENUM (
    'borrador',
    'pendiente_aprobacion',
    'aprobada',
    'rechazada',
    'convertida',
    'cancelada'
);

CREATE TYPE estado_orden_compra AS ENUM (
    'borrador',
    'emitida',
    'parcialmente_recibida',
    'recibida',
    'cerrada',
    'cancelada'
);

-- ---------------------------------------------------------------------------
-- Helpers: coherencia tenant en compras
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compras_validar_producto_misma_cuenta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
BEGIN
    IF TG_TABLE_NAME = 'solicitud_compra_linea' THEN
        SELECT sc.codigo_cuenta
        INTO v_codigo_cuenta
        FROM solicitud_compra sc
        WHERE sc.id_solicitud_compra = NEW.id_solicitud_compra;
    ELSE
        SELECT oc.codigo_cuenta
        INTO v_codigo_cuenta
        FROM orden_compra oc
        WHERE oc.id_orden_compra = NEW.id_orden_compra;
    END IF;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'documento padre no existe';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM producto p
        WHERE p.id_producto = NEW.id_producto
          AND p.codigo_cuenta = v_codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'producto % no pertenece a la cuenta del documento', NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION compras_validar_orden_compra_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id_proveedor IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM proveedor pr
            WHERE pr.id_proveedor = NEW.id_proveedor
              AND pr.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'proveedor % no pertenece a la cuenta %', NEW.id_proveedor, NEW.codigo_cuenta;
        END IF;
    END IF;

    IF NEW.id_solicitud_compra IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM solicitud_compra sc
            WHERE sc.id_solicitud_compra = NEW.id_solicitud_compra
              AND sc.codigo_cuenta = NEW.codigo_cuenta
              AND sc.id_bodega = NEW.id_bodega
        ) THEN
            RAISE EXCEPTION 'solicitud % no coincide con cuenta/bodega de la OC', NEW.id_solicitud_compra;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- solicitud_compra (SOL) — alcance C+B
-- ---------------------------------------------------------------------------
CREATE TABLE solicitud_compra (
    id_solicitud_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    estado estado_solicitud_compra NOT NULL DEFAULT 'borrador',
    id_solicitante uuid NOT NULL,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_solicitud_compra_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_solicitud_compra_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_solicitud_compra_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_solicitud_compra_solicitante
        FOREIGN KEY (id_solicitante)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_solicitud_compra_cuenta ON solicitud_compra (codigo_cuenta);
CREATE INDEX ix_solicitud_compra_bodega ON solicitud_compra (id_bodega);
CREATE INDEX ix_solicitud_compra_estado ON solicitud_compra (codigo_cuenta, estado);
CREATE INDEX ix_solicitud_compra_solicitante ON solicitud_compra (id_solicitante);

CREATE TRIGGER trg_solicitud_compra_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON solicitud_compra
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_solicitud_compra_updated_at
    BEFORE UPDATE ON solicitud_compra
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE solicitud_compra IS
    'Solicitud de compra (SOL). Desbloquea flujo POL-5 vía orden_compra. POL-33.';

-- ---------------------------------------------------------------------------
-- solicitud_compra_linea
-- ---------------------------------------------------------------------------
CREATE TABLE solicitud_compra_linea (
    id_linea_solicitud_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_solicitud_compra uuid NOT NULL,
    id_producto uuid NOT NULL,
    cantidad numeric(18, 4) NOT NULL,

    CONSTRAINT chk_solicitud_linea_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT fk_solicitud_linea_solicitud
        FOREIGN KEY (id_solicitud_compra)
        REFERENCES solicitud_compra (id_solicitud_compra)
        ON DELETE CASCADE,

    CONSTRAINT fk_solicitud_linea_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
);

CREATE INDEX ix_solicitud_linea_solicitud ON solicitud_compra_linea (id_solicitud_compra);
CREATE INDEX ix_solicitud_linea_producto ON solicitud_compra_linea (id_producto);

CREATE TRIGGER trg_solicitud_linea_validar_producto
    BEFORE INSERT OR UPDATE OF id_solicitud_compra, id_producto ON solicitud_compra_linea
    FOR EACH ROW
    EXECUTE FUNCTION compras_validar_producto_misma_cuenta();

COMMENT ON TABLE solicitud_compra_linea IS
    'Líneas de SOL. Mutaciones solo backend (NestJS). POL-33.';

-- ---------------------------------------------------------------------------
-- orden_compra (OC) — alcance C+B
-- ---------------------------------------------------------------------------
CREATE TABLE orden_compra (
    id_orden_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_proveedor uuid NOT NULL,
    id_solicitud_compra uuid,
    codigo varchar(32) NOT NULL,
    estado estado_orden_compra NOT NULL DEFAULT 'borrador',
    fecha_emision date NOT NULL DEFAULT CURRENT_DATE,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_orden_compra_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_orden_compra_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_orden_compra_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_orden_compra_proveedor
        FOREIGN KEY (id_proveedor)
        REFERENCES proveedor (id_proveedor),

    CONSTRAINT fk_orden_compra_solicitud
        FOREIGN KEY (id_solicitud_compra)
        REFERENCES solicitud_compra (id_solicitud_compra)
        ON DELETE SET NULL
);

CREATE INDEX ix_orden_compra_cuenta ON orden_compra (codigo_cuenta);
CREATE INDEX ix_orden_compra_bodega ON orden_compra (id_bodega);
CREATE INDEX ix_orden_compra_proveedor ON orden_compra (id_proveedor);
CREATE INDEX ix_orden_compra_estado ON orden_compra (codigo_cuenta, estado);
CREATE INDEX ix_orden_compra_solicitud ON orden_compra (id_solicitud_compra);

CREATE TRIGGER trg_orden_compra_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON orden_compra
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_orden_compra_validar_refs
    BEFORE INSERT OR UPDATE OF codigo_cuenta, id_bodega, id_proveedor, id_solicitud_compra
        ON orden_compra
    FOR EACH ROW
    EXECUTE FUNCTION compras_validar_orden_compra_referencias();

CREATE TRIGGER trg_orden_compra_updated_at
    BEFORE UPDATE ON orden_compra
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE orden_compra IS
    'Orden de compra (OC). Base para ingreso POL-5 (recepción). POL-33.';

-- ---------------------------------------------------------------------------
-- orden_compra_linea
-- ---------------------------------------------------------------------------
CREATE TABLE orden_compra_linea (
    id_linea_orden_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_compra uuid NOT NULL,
    id_producto uuid NOT NULL,
    cantidad numeric(18, 4) NOT NULL,
    precio_unitario numeric(18, 4) NOT NULL DEFAULT 0,
    cantidad_recibida numeric(18, 4) NOT NULL DEFAULT 0,

    CONSTRAINT chk_orden_linea_cantidad_positiva CHECK (cantidad > 0),
    CONSTRAINT chk_orden_linea_precio_no_negativo CHECK (precio_unitario >= 0),
    CONSTRAINT chk_orden_linea_recibida_no_negativa CHECK (cantidad_recibida >= 0),
    CONSTRAINT chk_orden_linea_recibida_max CHECK (cantidad_recibida <= cantidad),

    CONSTRAINT fk_orden_linea_orden
        FOREIGN KEY (id_orden_compra)
        REFERENCES orden_compra (id_orden_compra)
        ON DELETE CASCADE,

    CONSTRAINT fk_orden_linea_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
);

CREATE INDEX ix_orden_linea_orden ON orden_compra_linea (id_orden_compra);
CREATE INDEX ix_orden_linea_producto ON orden_compra_linea (id_producto);

CREATE TRIGGER trg_orden_linea_validar_producto
    BEFORE INSERT OR UPDATE OF id_orden_compra, id_producto ON orden_compra_linea
    FOR EACH ROW
    EXECUTE FUNCTION compras_validar_producto_misma_cuenta();

COMMENT ON TABLE orden_compra_linea IS
    'Líneas de OC. cantidad_recibida alimenta POL-5; mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado; sin INSERT/UPDATE/DELETE vía PostgREST
-- ---------------------------------------------------------------------------
ALTER TABLE solicitud_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE solicitud_compra_linea ENABLE ROW LEVEL SECURITY;
ALTER TABLE orden_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE orden_compra_linea ENABLE ROW LEVEL SECURITY;

CREATE POLICY solicitud_compra_select_scope
    ON solicitud_compra
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY solicitud_compra_linea_select_scope
    ON solicitud_compra_linea
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM solicitud_compra sc
            WHERE sc.id_solicitud_compra = solicitud_compra_linea.id_solicitud_compra
              AND auth_wms_puede_ver_cuenta(sc.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(sc.id_bodega)
        )
    );

CREATE POLICY orden_compra_select_scope
    ON orden_compra
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY orden_compra_linea_select_scope
    ON orden_compra_linea
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM orden_compra oc
            WHERE oc.id_orden_compra = orden_compra_linea.id_orden_compra
              AND auth_wms_puede_ver_cuenta(oc.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(oc.id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON solicitud_compra FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON solicitud_compra_linea FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON orden_compra FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON orden_compra_linea FROM authenticated;

GRANT SELECT ON solicitud_compra TO authenticated;
GRANT SELECT ON solicitud_compra_linea TO authenticated;
GRANT SELECT ON orden_compra TO authenticated;
GRANT SELECT ON orden_compra_linea TO authenticated;
