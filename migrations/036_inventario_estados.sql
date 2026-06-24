-- Alineación v1/v2: inventario — estados slot/lote y reservas (036).

-- ---------------------------------------------------------------------------
-- ubicacion — estado de slot (mapa POL-6)
-- ---------------------------------------------------------------------------
ALTER TABLE ubicacion
    ADD COLUMN estado_slot estado_slot NOT NULL DEFAULT 'libre';

CREATE INDEX ix_ubicacion_estado_slot ON ubicacion (id_bodega, estado_slot);

-- ---------------------------------------------------------------------------
-- lote — trazabilidad cliente y estado
-- ---------------------------------------------------------------------------
ALTER TABLE lote
    ADD COLUMN id_cliente uuid,
    ADD COLUMN estado_lote estado_lote NOT NULL DEFAULT 'activo',
    ADD COLUMN temperatura_objetivo numeric(8, 2);

ALTER TABLE lote
    ADD CONSTRAINT fk_lote_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente);

CREATE INDEX ix_lote_cliente ON lote (id_cliente)
    WHERE id_cliente IS NOT NULL;

CREATE INDEX ix_lote_estado ON lote (id_bodega, estado_lote);

-- ---------------------------------------------------------------------------
-- warehouse_state — cantidad reservada (doc POL-33)
-- ---------------------------------------------------------------------------
ALTER TABLE warehouse_state
    ADD COLUMN cantidad_reservada numeric(18, 4) NOT NULL DEFAULT 0;

ALTER TABLE warehouse_state
    ADD CONSTRAINT chk_warehouse_state_reservada_no_negativa
        CHECK (cantidad_reservada >= 0),
    ADD CONSTRAINT chk_warehouse_state_reservada_max
        CHECK (cantidad_reservada <= cantidad);

COMMENT ON COLUMN warehouse_state.cantidad_reservada IS
    'Stock reservado para OV/OT; disponible = cantidad - cantidad_reservada.';
