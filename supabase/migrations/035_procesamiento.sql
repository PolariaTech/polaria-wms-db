-- Alineación v1/v2: procesamiento y merma (035).

-- ---------------------------------------------------------------------------
-- solicitud_procesamiento
-- ---------------------------------------------------------------------------
CREATE TABLE solicitud_procesamiento (
    id_solicitud_procesamiento uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    id_cliente uuid,
    id_producto_primario uuid NOT NULL,
    id_producto_secundario uuid NOT NULL,
    id_solicitante uuid NOT NULL,
    id_procesador uuid,
    estado estado_procesamiento NOT NULL DEFAULT 'borrador',
    kilos_primario numeric(18, 4) NOT NULL,
    kilos_secundario numeric(18, 4),
    kilos_merma numeric(18, 4),
    sobrante_kg numeric(18, 4),
    regla_conversion_cantidad_primario numeric(18, 4),
    regla_conversion_unidades_secundario numeric(18, 4),
    perdida_procesamiento_pct numeric(5, 2),
    estimado_unidades_secundario numeric(18, 4),
    kg_primario_descontado numeric(18, 4),
    cierre_desde_procesador boolean NOT NULL DEFAULT false,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_solicitud_procesamiento_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT chk_solicitud_proc_kilos_primario_positivo CHECK (kilos_primario > 0),

    CONSTRAINT fk_sol_proc_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_sol_proc_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_sol_proc_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),

    CONSTRAINT fk_sol_proc_primario
        FOREIGN KEY (id_producto_primario)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_sol_proc_secundario
        FOREIGN KEY (id_producto_secundario)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_sol_proc_solicitante
        FOREIGN KEY (id_solicitante)
        REFERENCES usuario (id_usuario),

    CONSTRAINT fk_sol_proc_procesador
        FOREIGN KEY (id_procesador)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_sol_proc_cuenta ON solicitud_procesamiento (codigo_cuenta);
CREATE INDEX ix_sol_proc_bodega ON solicitud_procesamiento (id_bodega);
CREATE INDEX ix_sol_proc_estado ON solicitud_procesamiento (id_bodega, estado);

CREATE TRIGGER trg_sol_proc_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON solicitud_procesamiento
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_sol_proc_updated_at
    BEFORE UPDATE ON solicitud_procesamiento
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE solicitud_procesamiento IS
    'Solicitud de transformación primario→secundario (balance de masa v1).';

-- ---------------------------------------------------------------------------
-- registro_merma — reportes mensuales
-- ---------------------------------------------------------------------------
CREATE TABLE registro_merma (
    id_registro uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_solicitud_procesamiento uuid NOT NULL,
    id_bodega uuid NOT NULL,
    codigo_cuenta varchar(32) NOT NULL,
    kilos_merma numeric(18, 4) NOT NULL,
    periodo date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_registro_merma_kilos_positivo CHECK (kilos_merma >= 0),

    CONSTRAINT fk_registro_merma_solicitud
        FOREIGN KEY (id_solicitud_procesamiento)
        REFERENCES solicitud_procesamiento (id_solicitud_procesamiento),

    CONSTRAINT fk_registro_merma_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_registro_merma_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_registro_merma_periodo ON registro_merma (codigo_cuenta, periodo);
CREATE INDEX ix_registro_merma_bodega ON registro_merma (id_bodega);

COMMENT ON TABLE registro_merma IS
    'Merma consolidada por solicitud y periodo (primer día del mes).';

-- ---------------------------------------------------------------------------
-- orden_trabajo — vínculos v1 (caja, slots, solicitante, procesamiento)
-- ---------------------------------------------------------------------------
ALTER TABLE orden_trabajo
    ADD COLUMN id_solicitante uuid,
    ADD COLUMN id_lote uuid,
    ADD COLUMN id_ubicacion_origen uuid,
    ADD COLUMN id_ubicacion_destino uuid,
    ADD COLUMN id_solicitud_procesamiento uuid;

ALTER TABLE orden_trabajo
    ADD CONSTRAINT fk_ot_solicitante
        FOREIGN KEY (id_solicitante)
        REFERENCES usuario (id_usuario),

    ADD CONSTRAINT fk_ot_lote
        FOREIGN KEY (id_lote)
        REFERENCES lote (id_lote),

    ADD CONSTRAINT fk_ot_ubicacion_origen
        FOREIGN KEY (id_ubicacion_origen)
        REFERENCES ubicacion (id_ubicacion),

    ADD CONSTRAINT fk_ot_ubicacion_destino
        FOREIGN KEY (id_ubicacion_destino)
        REFERENCES ubicacion (id_ubicacion),

    ADD CONSTRAINT fk_ot_solicitud_procesamiento
        FOREIGN KEY (id_solicitud_procesamiento)
        REFERENCES solicitud_procesamiento (id_solicitud_procesamiento)
        ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE solicitud_procesamiento ENABLE ROW LEVEL SECURITY;
ALTER TABLE registro_merma ENABLE ROW LEVEL SECURITY;

CREATE POLICY solicitud_procesamiento_select_scope
    ON solicitud_procesamiento
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY registro_merma_select_scope
    ON registro_merma
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON solicitud_procesamiento FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON registro_merma FROM authenticated;

GRANT SELECT ON solicitud_procesamiento TO authenticated;
GRANT SELECT ON registro_merma TO authenticated;
