-- Alineación v1/v2: ventas ampliadas (038).

ALTER TABLE orden_venta
    ADD COLUMN id_comprador uuid,
    ADD COLUMN id_planta uuid,
    ADD COLUMN id_creador uuid,
    ADD COLUMN id_bodega_destino uuid;

ALTER TABLE orden_venta
    ADD CONSTRAINT fk_orden_venta_comprador
        FOREIGN KEY (id_comprador)
        REFERENCES comprador (id_comprador),

    ADD CONSTRAINT fk_orden_venta_planta
        FOREIGN KEY (id_planta)
        REFERENCES planta (id_planta),

    ADD CONSTRAINT fk_orden_venta_creador
        FOREIGN KEY (id_creador)
        REFERENCES usuario (id_usuario),

    ADD CONSTRAINT fk_orden_venta_bodega_destino
        FOREIGN KEY (id_bodega_destino)
        REFERENCES bodega (id_bodega);

CREATE INDEX ix_orden_venta_comprador ON orden_venta (id_comprador)
    WHERE id_comprador IS NOT NULL;

CREATE INDEX ix_orden_venta_planta ON orden_venta (id_planta)
    WHERE id_planta IS NOT NULL;

COMMENT ON COLUMN orden_venta.id_cliente IS
    'Cliente dueño del catálogo / mercancía (v1 idClienteDueno).';

COMMENT ON COLUMN orden_venta.id_comprador IS
    'Destino comercial de la OV (v1 compradorId).';

COMMENT ON COLUMN orden_venta.id_bodega_destino IS
    'Bodega destino cuando la venta cruza bodegas internas (v1 destinoWarehouseId).';
