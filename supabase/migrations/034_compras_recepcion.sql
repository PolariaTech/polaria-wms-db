-- Alineación v1/v2: compras ampliadas + recepción (034).

-- ---------------------------------------------------------------------------
-- solicitud_compra — proveedor y enlace OC
-- ---------------------------------------------------------------------------
ALTER TABLE solicitud_compra
    ADD COLUMN id_proveedor uuid,
    ADD COLUMN id_orden_compra uuid;

ALTER TABLE solicitud_compra
    ADD CONSTRAINT fk_solicitud_compra_proveedor
        FOREIGN KEY (id_proveedor)
        REFERENCES proveedor (id_proveedor),

    ADD CONSTRAINT fk_solicitud_compra_orden
        FOREIGN KEY (id_orden_compra)
        REFERENCES orden_compra (id_orden_compra)
        ON DELETE SET NULL;

CREATE INDEX ix_solicitud_compra_proveedor ON solicitud_compra (id_proveedor)
    WHERE id_proveedor IS NOT NULL;

-- ---------------------------------------------------------------------------
-- orden_compra — creador, entrega, destino
-- ---------------------------------------------------------------------------
ALTER TABLE orden_compra
    ADD COLUMN id_creador uuid,
    ADD COLUMN fecha_entrega_estimada date,
    ADD COLUMN destino_tipo destino_tipo NOT NULL DEFAULT 'interna';

ALTER TABLE orden_compra
    ADD CONSTRAINT fk_orden_compra_creador
        FOREIGN KEY (id_creador)
        REFERENCES usuario (id_usuario);

-- ---------------------------------------------------------------------------
-- recepcion_compra — conciliación al ingreso (v1 OrdenCompra.recepcion)
-- ---------------------------------------------------------------------------
CREATE TABLE recepcion_compra (
    id_recepcion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_orden_compra uuid NOT NULL,
    sin_diferencias boolean NOT NULL DEFAULT false,
    notas text,
    cerrada_at timestamptz NOT NULL DEFAULT now(),
    cerrada_por uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_recepcion_orden UNIQUE (id_orden_compra),

    CONSTRAINT fk_recepcion_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_recepcion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_recepcion_orden
        FOREIGN KEY (id_orden_compra)
        REFERENCES orden_compra (id_orden_compra),

    CONSTRAINT fk_recepcion_cerrada_por
        FOREIGN KEY (cerrada_por)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_recepcion_bodega ON recepcion_compra (id_bodega);
CREATE INDEX ix_recepcion_cuenta ON recepcion_compra (codigo_cuenta);

CREATE TABLE recepcion_compra_linea (
    id_linea_recepcion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_recepcion uuid NOT NULL,
    id_linea_orden_compra uuid,
    id_producto uuid,
    cantidad_recibida numeric(18, 4) NOT NULL,
    temperatura_registrada numeric(8, 2),
    es_adicional boolean NOT NULL DEFAULT false,
    titulo_snapshot varchar(512),

    CONSTRAINT chk_recepcion_linea_cantidad_positiva CHECK (cantidad_recibida >= 0),

    CONSTRAINT fk_recepcion_linea_recepcion
        FOREIGN KEY (id_recepcion)
        REFERENCES recepcion_compra (id_recepcion)
        ON DELETE CASCADE,

    CONSTRAINT fk_recepcion_linea_oc
        FOREIGN KEY (id_linea_orden_compra)
        REFERENCES orden_compra_linea (id_linea_orden_compra)
        ON DELETE SET NULL,

    CONSTRAINT fk_recepcion_linea_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
);

CREATE INDEX ix_recepcion_linea_recepcion ON recepcion_compra_linea (id_recepcion);

COMMENT ON TABLE recepcion_compra IS
    'Cierre de recepción física contra OC (conciliación ciega POL-5).';

COMMENT ON TABLE recepcion_compra_linea IS
    'Líneas de recepción; es_adicional=true para productos no pedidos en la OC.';

-- ---------------------------------------------------------------------------
-- RLS — recepción solo backend (como compras operativas)
-- ---------------------------------------------------------------------------
ALTER TABLE recepcion_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE recepcion_compra_linea ENABLE ROW LEVEL SECURITY;

CREATE POLICY recepcion_compra_select_scope
    ON recepcion_compra
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY recepcion_compra_linea_select_scope
    ON recepcion_compra_linea
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM recepcion_compra r
            WHERE r.id_recepcion = recepcion_compra_linea.id_recepcion
              AND auth_wms_puede_ver_cuenta(r.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(r.id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON recepcion_compra FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON recepcion_compra_linea FROM authenticated;

GRANT SELECT ON recepcion_compra TO authenticated;
GRANT SELECT ON recepcion_compra_linea TO authenticated;
