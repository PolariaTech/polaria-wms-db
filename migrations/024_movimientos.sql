-- POL-33 Fase 5: movimiento_inventario — historial append-only de trazabilidad.
--
-- Depende de warehouse_state (023). Sin triggers automáticos a stock en vivo;
-- el backend (POL-5+) ejecutará transacciones atómicas movimiento + warehouse_state.
--
-- RLS (docs/modelo-operativo-v2.md): SELECT acotado por bodega; escritura **B** (solo backend).
-- Complementa docs/rls-politicas.md § tablas sensibles (movimientos).

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE tipo_movimiento AS ENUM (
    'entrada',
    'salida',
    'recepcion',
    'despacho',
    'transferencia',
    'ajuste_positivo',
    'ajuste_negativo',
    'merma',
    'reserva',
    'liberacion_reserva',
    'consumo_ot',
    'produccion_ot'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION movimiento_inventario_validar_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id_ubicacion_origen IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ubicacion u
            WHERE u.id_ubicacion = NEW.id_ubicacion_origen
              AND u.id_bodega = NEW.id_bodega
              AND u.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'ubicacion origen % no pertenece a bodega/cuenta', NEW.id_ubicacion_origen;
        END IF;
    END IF;

    IF NEW.id_ubicacion_destino IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ubicacion u
            WHERE u.id_ubicacion = NEW.id_ubicacion_destino
              AND u.id_bodega = NEW.id_bodega
              AND u.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'ubicacion destino % no pertenece a bodega/cuenta', NEW.id_ubicacion_destino;
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM producto p
        WHERE p.id_producto = NEW.id_producto
          AND p.codigo_cuenta = NEW.codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'producto % no pertenece a la cuenta %', NEW.id_producto, NEW.codigo_cuenta;
    END IF;

    IF NEW.id_lote IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM lote l
            WHERE l.id_lote = NEW.id_lote
              AND l.id_bodega = NEW.id_bodega
              AND l.id_producto = NEW.id_producto
              AND l.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'lote % no coincide con bodega/producto/cuenta', NEW.id_lote;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION movimiento_inventario_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'movimiento_inventario es append-only; no UPDATE ni DELETE';
END;
$$;

-- ---------------------------------------------------------------------------
-- movimiento_inventario — ledger de inventario (sin updated_at)
-- ---------------------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento_inventario uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_ubicacion_origen uuid,
    id_ubicacion_destino uuid,
    id_producto uuid NOT NULL,
    id_lote uuid,
    cantidad numeric(18, 4) NOT NULL,
    tipo_movimiento tipo_movimiento NOT NULL,
    id_usuario uuid NOT NULL,
    id_referencia uuid,
    tipo_referencia varchar(32),
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_movimiento_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT chk_movimiento_ubicacion_presente CHECK (
        id_ubicacion_origen IS NOT NULL
        OR id_ubicacion_destino IS NOT NULL
    ),

    CONSTRAINT chk_movimiento_referencia_par CHECK (
        (tipo_referencia IS NULL AND id_referencia IS NULL)
        OR (tipo_referencia IS NOT NULL AND id_referencia IS NOT NULL)
    ),

    CONSTRAINT chk_movimiento_tipo_referencia CHECK (
        tipo_referencia IS NULL
        OR tipo_referencia IN (
            'orden_compra',
            'orden_trabajo',
            'orden_venta',
            'solicitud_compra',
            'manual'
        )
    ),

    CONSTRAINT fk_movimiento_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_movimiento_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_movimiento_ubicacion_origen
        FOREIGN KEY (id_ubicacion_origen)
        REFERENCES ubicacion (id_ubicacion),

    CONSTRAINT fk_movimiento_ubicacion_destino
        FOREIGN KEY (id_ubicacion_destino)
        REFERENCES ubicacion (id_ubicacion),

    CONSTRAINT fk_movimiento_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_movimiento_lote
        FOREIGN KEY (id_lote)
        REFERENCES lote (id_lote),

    CONSTRAINT fk_movimiento_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_movimiento_cuenta ON movimiento_inventario (codigo_cuenta);
CREATE INDEX ix_movimiento_bodega ON movimiento_inventario (id_bodega);
CREATE INDEX ix_movimiento_bodega_created ON movimiento_inventario (id_bodega, created_at DESC);
CREATE INDEX ix_movimiento_producto ON movimiento_inventario (id_producto);
CREATE INDEX ix_movimiento_lote ON movimiento_inventario (id_lote)
    WHERE id_lote IS NOT NULL;
CREATE INDEX ix_movimiento_tipo ON movimiento_inventario (id_bodega, tipo_movimiento);
CREATE INDEX ix_movimiento_referencia ON movimiento_inventario (tipo_referencia, id_referencia)
    WHERE id_referencia IS NOT NULL;
CREATE INDEX ix_movimiento_usuario ON movimiento_inventario (id_usuario);

CREATE TRIGGER trg_movimiento_sync_cuenta
    BEFORE INSERT ON movimiento_inventario
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_movimiento_validar_refs
    BEFORE INSERT ON movimiento_inventario
    FOR EACH ROW
    EXECUTE FUNCTION movimiento_inventario_validar_referencias();

CREATE TRIGGER trg_movimiento_append_only
    BEFORE UPDATE OR DELETE ON movimiento_inventario
    FOR EACH ROW
    EXECUTE FUNCTION movimiento_inventario_append_only();

COMMENT ON TABLE movimiento_inventario IS
    'Historial append-only de movimientos de inventario. Escritura solo backend. POL-33.';

COMMENT ON COLUMN movimiento_inventario.tipo_referencia IS
    'Documento origen: orden_compra | orden_trabajo | orden_venta | solicitud_compra | manual';

COMMENT ON COLUMN movimiento_inventario.metadata IS
    'Payload extensible (motivo ajuste, temperatura, id línea OC, etc.)';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado (doc V2); escritura solo postgres / service role
-- ---------------------------------------------------------------------------
ALTER TABLE movimiento_inventario ENABLE ROW LEVEL SECURITY;

CREATE POLICY movimiento_inventario_select_scope
    ON movimiento_inventario
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON movimiento_inventario FROM authenticated;

GRANT SELECT ON movimiento_inventario TO authenticated;

-- Decisión documentada: SELECT vía PostgREST para operadores con alcance de bodega
-- (historial en UI). INSERT/UPDATE/DELETE revocados; el backend NestJS persiste
-- movimientos en transacción con warehouse_state (POL-5+).
