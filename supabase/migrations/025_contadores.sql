-- POL-33 Fase 6a: contador — secuencias numéricas por cuenta / bodega.
--
-- Alcance: codigo_cuenta + id_bodega nullable (NULL = secuencia a nivel cuenta).
-- docs/modelo-operativo-v2.md: sin SELECT PostgREST (**—**); escritura **B** (solo backend).
-- Complementa docs/rls-politicas.md § tablas sensibles.

-- ---------------------------------------------------------------------------
-- contador
-- ---------------------------------------------------------------------------
CREATE TABLE contador (
    id_contador uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid,
    clave varchar(32) NOT NULL,
    valor bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_contador_cuenta_bodega_clave UNIQUE NULLS NOT DISTINCT (
        codigo_cuenta,
        id_bodega,
        clave
    ),

    CONSTRAINT chk_contador_valor_no_negativo CHECK (valor >= 0),

    CONSTRAINT fk_contador_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_contador_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
);

CREATE INDEX ix_contador_cuenta ON contador (codigo_cuenta);
CREATE INDEX ix_contador_bodega ON contador (id_bodega)
    WHERE id_bodega IS NOT NULL;

CREATE TRIGGER trg_contador_updated_at
    BEFORE UPDATE ON contador
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE contador IS
    'Secuencias atómicas (OC, SOL, OT, …). id_bodega NULL = ámbito cuenta. Solo backend. POL-33.';

COMMENT ON COLUMN contador.clave IS
    'Identificador lógico: OC, SOL, OT, OV, lote, movimiento_inventario, etc.';

-- PK surrogate: id_bodega nullable impide PK compuesta (codigo_cuenta, id_bodega, clave).
-- Unicidad de negocio vía uq_contador_cuenta_bodega_clave (NULLS NOT DISTINCT).

-- ---------------------------------------------------------------------------
-- RLS — sin exposición a authenticated (doc V2: SELECT **—**)
-- ---------------------------------------------------------------------------
ALTER TABLE contador ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON contador FROM authenticated;

-- Sin políticas para authenticated: acceso exclusivo vía postgres / service role (backend).
