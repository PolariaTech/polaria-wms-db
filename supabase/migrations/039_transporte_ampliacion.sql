-- Alineación v1/v2: transporte ampliado (039).

ALTER TABLE viaje_transporte
    ADD COLUMN id_camion uuid;

ALTER TABLE viaje_transporte
    ADD CONSTRAINT fk_viaje_camion
        FOREIGN KEY (id_camion)
        REFERENCES camion (id_camion);

CREATE INDEX ix_viaje_camion ON viaje_transporte (id_camion)
    WHERE id_camion IS NOT NULL;

ALTER TABLE evidencia_transporte
    ADD COLUMN id_linea_orden_venta uuid,
    ADD COLUMN cantidad_entregada numeric(18, 4),
    ADD COLUMN incidencia text,
    ADD COLUMN entrega_conforme boolean;

ALTER TABLE evidencia_transporte
    ADD CONSTRAINT fk_evidencia_linea_ov
        FOREIGN KEY (id_linea_orden_venta)
        REFERENCES orden_venta_linea (id_linea_orden_venta)
        ON DELETE SET NULL;

COMMENT ON COLUMN evidencia_transporte.cantidad_entregada IS
    'Kg o unidades entregadas por línea OV (v1 ViajeLineaEntrega).';

COMMENT ON COLUMN evidencia_transporte.entrega_conforme IS
    'true = conforme con lo esperado (v1 entregaConforme).';
