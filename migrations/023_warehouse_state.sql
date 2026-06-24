-- POL-33 Fase 4: warehouse_state — inventario en vivo / mapa de bodega.
--
-- Crítico para POL-6 (mapa tiempo real vía Supabase Realtime).
-- Patrón sensible (018_rls_write_policies.sql): REVOKE escritura a authenticated;
-- SELECT acotado por bodega; mutaciones solo backend (postgres / service role).
-- Complementa docs/rls-politicas.md § tablas sensibles (warehouse_state).
--
-- Sin triggers de movimiento_inventario (migración posterior).

-- ---------------------------------------------------------------------------
-- lote — mínimo para FK nullable en warehouse_state (trazabilidad V2.1)
-- ---------------------------------------------------------------------------
CREATE TABLE lote (
    id_lote uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_producto uuid NOT NULL,
    codigo_lote varchar(64) NOT NULL,
    fecha_vencimiento date,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_lote_bodega_producto_codigo UNIQUE (id_bodega, id_producto, codigo_lote),

    CONSTRAINT fk_lote_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_lote_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_lote_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
);

CREATE INDEX ix_lote_cuenta ON lote (codigo_cuenta);
CREATE INDEX ix_lote_bodega ON lote (id_bodega);
CREATE INDEX ix_lote_producto ON lote (id_producto);

CREATE TRIGGER trg_lote_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON lote
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_lote_updated_at
    BEFORE UPDATE ON lote
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE lote IS
    'Lote mínimo para warehouse_state.id_lote. Ampliación (estado_lote) en migración futura. POL-33.';

-- ---------------------------------------------------------------------------
-- Helpers: coherencia warehouse_state ↔ bodega / ubicación / producto / lote
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION warehouse_state_validar_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM ubicacion u
        WHERE u.id_ubicacion = NEW.id_ubicacion
          AND u.id_bodega = NEW.id_bodega
          AND u.codigo_cuenta = NEW.codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'ubicacion % no pertenece a bodega/cuenta del stock', NEW.id_ubicacion;
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

    IF NEW.locked_by IS NOT NULL AND NEW.locked_at IS NULL THEN
        RAISE EXCEPTION 'locked_at requerido cuando locked_by está definido';
    END IF;

    IF NEW.locked_by IS NULL AND NEW.locked_at IS NOT NULL THEN
        RAISE EXCEPTION 'locked_by requerido cuando locked_at está definido';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION warehouse_state_bump_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.version := OLD.version + 1;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- warehouse_state — foto de stock por ubicación × producto × lote (opcional)
-- ---------------------------------------------------------------------------
CREATE TABLE warehouse_state (
    id_warehouse_state uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_ubicacion uuid NOT NULL,
    id_producto uuid NOT NULL,
    id_lote uuid,
    cantidad numeric(18, 4) NOT NULL,
    temperatura numeric(8, 2),
    locked_by uuid,
    locked_at timestamptz,
    version integer NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_warehouse_state_cantidad_no_negativa CHECK (cantidad >= 0),

    CONSTRAINT uq_warehouse_state_slot UNIQUE NULLS NOT DISTINCT (
        id_ubicacion,
        id_producto,
        id_lote
    ),

    CONSTRAINT fk_warehouse_state_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_warehouse_state_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_warehouse_state_ubicacion
        FOREIGN KEY (id_ubicacion)
        REFERENCES ubicacion (id_ubicacion),

    CONSTRAINT fk_warehouse_state_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_warehouse_state_lote
        FOREIGN KEY (id_lote)
        REFERENCES lote (id_lote),

    CONSTRAINT fk_warehouse_state_locked_by
        FOREIGN KEY (locked_by)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_warehouse_state_bodega ON warehouse_state (id_bodega);
CREATE INDEX ix_warehouse_state_ubicacion ON warehouse_state (id_ubicacion);
CREATE INDEX ix_warehouse_state_producto ON warehouse_state (id_producto);
CREATE INDEX ix_warehouse_state_cuenta ON warehouse_state (codigo_cuenta);
CREATE INDEX ix_warehouse_state_lote ON warehouse_state (id_lote)
    WHERE id_lote IS NOT NULL;

CREATE TRIGGER trg_warehouse_state_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON warehouse_state
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_warehouse_state_validar_refs
    BEFORE INSERT OR UPDATE OF codigo_cuenta, id_bodega, id_ubicacion, id_producto, id_lote, locked_by, locked_at
        ON warehouse_state
    FOR EACH ROW
    EXECUTE FUNCTION warehouse_state_validar_referencias();

CREATE TRIGGER trg_warehouse_state_bump_version
    BEFORE UPDATE ON warehouse_state
    FOR EACH ROW
    EXECUTE FUNCTION warehouse_state_bump_version();

CREATE TRIGGER trg_warehouse_state_updated_at
    BEFORE UPDATE ON warehouse_state
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE warehouse_state IS
    'Stock en vivo por slot (ubicación × producto × lote). Lectura Realtime POL-6; escritura solo backend. POL-33.';

COMMENT ON COLUMN warehouse_state.version IS
    'Optimistic locking: backend debe enviar version esperada en UPDATE.';

-- ---------------------------------------------------------------------------
-- RLS — lote y warehouse_state: solo lectura vía PostgREST
-- ---------------------------------------------------------------------------
ALTER TABLE lote ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY lote_select_scope
    ON lote
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

CREATE POLICY warehouse_state_select_scope
    ON warehouse_state
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON lote FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON warehouse_state FROM authenticated;

GRANT SELECT ON lote TO authenticated;
GRANT SELECT ON warehouse_state TO authenticated;

-- ---------------------------------------------------------------------------
-- Supabase Realtime (POL-6 mapa). Omitir si la publicación no existe.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_publication
        WHERE pubname = 'supabase_realtime'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE warehouse_state;
    ELSE
        RAISE NOTICE
            'Publicación supabase_realtime no encontrada. '
            'Para POL-6 ejecutar manualmente: '
            'ALTER PUBLICATION supabase_realtime ADD TABLE warehouse_state;';
    END IF;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'warehouse_state ya está en supabase_realtime';
END;
$$;
