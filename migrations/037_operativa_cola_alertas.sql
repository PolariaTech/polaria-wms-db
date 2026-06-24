-- Alineación v1/v2: cola operativa — alertas y tareas (037).

-- ---------------------------------------------------------------------------
-- alerta_operativa
-- ---------------------------------------------------------------------------
CREATE TABLE alerta_operativa (
    id_alerta uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    tipo tipo_alerta NOT NULL,
    estado estado_alerta NOT NULL DEFAULT 'abierta',
    id_ubicacion uuid,
    id_orden_trabajo uuid,
    id_responsable uuid,
    titulo varchar(255) NOT NULL,
    descripcion text,
    motivo_cierre text,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    cerrada_at timestamptz,

    CONSTRAINT fk_alerta_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_alerta_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_alerta_ubicacion
        FOREIGN KEY (id_ubicacion)
        REFERENCES ubicacion (id_ubicacion),

    CONSTRAINT fk_alerta_orden_trabajo
        FOREIGN KEY (id_orden_trabajo)
        REFERENCES orden_trabajo (id_orden_trabajo)
        ON DELETE SET NULL,

    CONSTRAINT fk_alerta_responsable
        FOREIGN KEY (id_responsable)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_alerta_bodega_estado ON alerta_operativa (id_bodega, estado);
CREATE INDEX ix_alerta_abierta ON alerta_operativa (id_bodega, created_at DESC)
    WHERE estado = 'abierta';

CREATE TRIGGER trg_alerta_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON alerta_operativa
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

COMMENT ON TABLE alerta_operativa IS
    'Alertas operativas: temperatura, demoras, órdenes reportadas (v1 alerts).';

-- ---------------------------------------------------------------------------
-- tarea_cola
-- ---------------------------------------------------------------------------
CREATE TABLE tarea_cola (
    id_tarea uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    tipo tipo_tarea NOT NULL DEFAULT 'otro',
    estado estado_tarea NOT NULL DEFAULT 'pendiente',
    id_asignado uuid,
    id_orden_trabajo uuid,
    titulo varchar(255),
    descripcion text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_tarea_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_tarea_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_tarea_asignado
        FOREIGN KEY (id_asignado)
        REFERENCES usuario (id_usuario),

    CONSTRAINT fk_tarea_orden_trabajo
        FOREIGN KEY (id_orden_trabajo)
        REFERENCES orden_trabajo (id_orden_trabajo)
        ON DELETE SET NULL
);

CREATE INDEX ix_tarea_cola_bodega_estado ON tarea_cola (id_bodega, estado, created_at);
CREATE INDEX ix_tarea_cola_asignado ON tarea_cola (id_asignado)
    WHERE id_asignado IS NOT NULL;

CREATE TRIGGER trg_tarea_cola_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON tarea_cola
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_tarea_cola_updated_at
    BEFORE UPDATE ON tarea_cola
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE tarea_cola IS
    'Cola operativa del operario (v1 state/main.tasks).';

-- ---------------------------------------------------------------------------
-- RLS — lectura bodega; mutaciones backend
-- ---------------------------------------------------------------------------
ALTER TABLE alerta_operativa ENABLE ROW LEVEL SECURITY;
ALTER TABLE tarea_cola ENABLE ROW LEVEL SECURITY;

CREATE POLICY alerta_operativa_select_scope
    ON alerta_operativa
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

CREATE POLICY tarea_cola_select_scope
    ON tarea_cola
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON alerta_operativa FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON tarea_cola FROM authenticated;

GRANT SELECT ON alerta_operativa TO authenticated;
GRANT SELECT ON tarea_cola TO authenticated;

-- Realtime para cola y alertas (mapa/dashboard)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE alerta_operativa;
        ALTER PUBLICATION supabase_realtime ADD TABLE tarea_cola;
    END IF;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;
