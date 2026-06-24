-- POL-33 Fase 1: layout de bodega (tipo_ubicacion, zona, ubicacion).
--
-- Convención tenant (017): codigo_cuenta + id_bodega en tablas operativas de layout.
-- codigo_cuenta se sincroniza desde bodega vía trigger (no duplicar codigo_empresa).
--
-- Escritura: solo backend (polaria-wms-api / rol postgres). PostgREST = SELECT acotado.
-- Ver docs/modelo-operativo-v2.md y docs/rls-politicas.md.

-- ---------------------------------------------------------------------------
-- Helpers: coherencia tenant layout ↔ bodega
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION layout_sync_codigo_cuenta_desde_bodega()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
BEGIN
    SELECT b.codigo_cuenta
    INTO v_codigo_cuenta
    FROM bodega b
    WHERE b.id_bodega = NEW.id_bodega;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'bodega % no existe', NEW.id_bodega;
    END IF;

    NEW.codigo_cuenta := v_codigo_cuenta;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ubicacion_validar_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id_zona IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM zona z
            WHERE z.id_zona = NEW.id_zona
              AND z.id_bodega = NEW.id_bodega
        ) THEN
            RAISE EXCEPTION 'zona % no pertenece a bodega %', NEW.id_zona, NEW.id_bodega;
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM tipo_ubicacion tu
        WHERE tu.id_tipo_ubicacion = NEW.id_tipo_ubicacion
          AND tu.id_bodega = NEW.id_bodega
    ) THEN
        RAISE EXCEPTION 'tipo_ubicacion % no pertenece a bodega %', NEW.id_tipo_ubicacion, NEW.id_bodega;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- tipo_ubicacion — catálogo por bodega (C+B)
-- ---------------------------------------------------------------------------
CREATE TABLE tipo_ubicacion (
    id_tipo_ubicacion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    es_picking boolean NOT NULL DEFAULT false,
    es_recepcion boolean NOT NULL DEFAULT false,
    es_almacenamiento boolean NOT NULL DEFAULT true,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_tipo_ubicacion_bodega_codigo UNIQUE (id_bodega, codigo),

    CONSTRAINT fk_tipo_ubicacion_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_tipo_ubicacion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
);

CREATE INDEX ix_tipo_ubicacion_cuenta ON tipo_ubicacion (codigo_cuenta);
CREATE INDEX ix_tipo_ubicacion_bodega ON tipo_ubicacion (id_bodega);

CREATE TRIGGER trg_tipo_ubicacion_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON tipo_ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_tipo_ubicacion_updated_at
    BEFORE UPDATE ON tipo_ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE tipo_ubicacion IS
    'Catálogo de tipos de ubicación por bodega (picking, recepción, almacenamiento). POL-33.';

-- ---------------------------------------------------------------------------
-- zona — agrupación lógica dentro de una bodega
-- ---------------------------------------------------------------------------
CREATE TABLE zona (
    id_zona uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_zona_bodega_codigo UNIQUE (id_bodega, codigo),

    CONSTRAINT fk_zona_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_zona_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
);

CREATE INDEX ix_zona_cuenta ON zona (codigo_cuenta);
CREATE INDEX ix_zona_bodega ON zona (id_bodega);

CREATE TRIGGER trg_zona_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON zona
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_zona_updated_at
    BEFORE UPDATE ON zona
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE zona IS
    'Zona lógica dentro de una bodega. POL-33.';

-- ---------------------------------------------------------------------------
-- ubicacion — posición física (bin, pasillo, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE ubicacion (
    id_ubicacion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_zona uuid,
    id_tipo_ubicacion uuid NOT NULL,
    codigo varchar(64) NOT NULL,
    capacidad numeric(18, 4),
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_ubicacion_bodega_codigo UNIQUE (id_bodega, codigo),

    CONSTRAINT fk_ubicacion_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_ubicacion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_ubicacion_zona
        FOREIGN KEY (id_zona)
        REFERENCES zona (id_zona),

    CONSTRAINT fk_ubicacion_tipo
        FOREIGN KEY (id_tipo_ubicacion)
        REFERENCES tipo_ubicacion (id_tipo_ubicacion)
);

CREATE INDEX ix_ubicacion_cuenta ON ubicacion (codigo_cuenta);
CREATE INDEX ix_ubicacion_bodega ON ubicacion (id_bodega);
CREATE INDEX ix_ubicacion_zona ON ubicacion (id_zona);
CREATE INDEX ix_ubicacion_tipo ON ubicacion (id_tipo_ubicacion);

CREATE TRIGGER trg_ubicacion_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_ubicacion_validar_refs
    BEFORE INSERT OR UPDATE OF id_bodega, id_zona, id_tipo_ubicacion ON ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION ubicacion_validar_referencias();

CREATE TRIGGER trg_ubicacion_updated_at
    BEFORE UPDATE ON ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE ubicacion IS
    'Ubicación física dentro de una bodega. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — lectura acotada; mutaciones solo backend (postgres bypass RLS)
-- ---------------------------------------------------------------------------
ALTER TABLE tipo_ubicacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE zona ENABLE ROW LEVEL SECURITY;
ALTER TABLE ubicacion ENABLE ROW LEVEL SECURITY;

CREATE POLICY tipo_ubicacion_select_scope
    ON tipo_ubicacion
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY zona_select_scope
    ON zona
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

CREATE POLICY ubicacion_select_scope
    ON ubicacion
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON tipo_ubicacion FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON zona FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON ubicacion FROM authenticated;

GRANT SELECT ON tipo_ubicacion TO authenticated;
GRANT SELECT ON zona TO authenticated;
GRANT SELECT ON ubicacion TO authenticated;
