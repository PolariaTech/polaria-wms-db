-- Alineación v1/v2: ampliación catálogos y producto primario/secundario (033).

-- ---------------------------------------------------------------------------
-- proveedor
-- ---------------------------------------------------------------------------
ALTER TABLE proveedor
    ADD COLUMN telefono varchar(32),
    ADD COLUMN email citext;

-- ---------------------------------------------------------------------------
-- cliente
-- ---------------------------------------------------------------------------
ALTER TABLE cliente
    ADD COLUMN nit varchar(32);

-- ---------------------------------------------------------------------------
-- comprador
-- ---------------------------------------------------------------------------
ALTER TABLE comprador
    ADD COLUMN contacto varchar(255);

-- ---------------------------------------------------------------------------
-- planta
-- ---------------------------------------------------------------------------
ALTER TABLE planta
    ADD COLUMN direccion text,
    ADD COLUMN capacidad_pallets integer,
    ADD COLUMN rango_temperatura varchar(64);

-- ---------------------------------------------------------------------------
-- camion
-- ---------------------------------------------------------------------------
ALTER TABLE camion
    ADD COLUMN codigo varchar(32),
    ADD COLUMN marca varchar(64),
    ADD COLUMN modelo varchar(64),
    ADD COLUMN capacidad_kg numeric(18, 4),
    ADD COLUMN capacidad_m3 numeric(18, 4),
    ADD COLUMN capacidad_pallets integer,
    ADD COLUMN tipo tipo_camion NOT NULL DEFAULT 'refrigerado',
    ADD COLUMN rango_temperatura varchar(64),
    ADD COLUMN disponible boolean NOT NULL DEFAULT true;

CREATE UNIQUE INDEX uq_camion_cuenta_codigo
    ON camion (codigo_cuenta, codigo)
    WHERE codigo IS NOT NULL;

-- ---------------------------------------------------------------------------
-- producto — primario/secundario, conversión, cliente dueño
-- ---------------------------------------------------------------------------
ALTER TABLE producto
    ADD COLUMN id_cliente uuid,
    ADD COLUMN es_primario boolean NOT NULL DEFAULT false,
    ADD COLUMN es_secundario boolean NOT NULL DEFAULT false,
    ADD COLUMN codigo_almacen varchar(32),
    ADD COLUMN id_producto_primario uuid,
    ADD COLUMN regla_conversion_cantidad_primario numeric(18, 4),
    ADD COLUMN regla_conversion_unidades_secundario numeric(18, 4),
    ADD COLUMN merma_pct numeric(5, 2),
    ADD COLUMN unidad_visualizacion varchar(32) NOT NULL DEFAULT 'peso';

ALTER TABLE producto
    ADD CONSTRAINT fk_producto_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),

    ADD CONSTRAINT fk_producto_primario
        FOREIGN KEY (id_producto_primario)
        REFERENCES producto (id_producto);

CREATE INDEX ix_producto_cliente ON producto (id_cliente)
    WHERE id_cliente IS NOT NULL;

CREATE INDEX ix_producto_primario ON producto (id_producto_primario)
    WHERE id_producto_primario IS NOT NULL;

CREATE UNIQUE INDEX uq_producto_cuenta_codigo_almacen
    ON producto (codigo_cuenta, codigo_almacen)
    WHERE codigo_almacen IS NOT NULL;

COMMENT ON COLUMN producto.codigo_almacen IS
    'Correlación slot↔catálogo (v1 almacenProductCode).';

COMMENT ON COLUMN producto.unidad_visualizacion IS
    'Preset UI: peso, cantidad, bolsas, cajas, etc.';
