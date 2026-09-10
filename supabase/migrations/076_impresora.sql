-- Impresoras carta (Letter) configuradas desde el configurador Polaria.
-- Conexión Wi‑Fi/Ethernet (IPP / JetDirect 9100) o USB vía agente local.

CREATE TABLE IF NOT EXISTS public.impresora (
    id_impresora uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NULL,
    nombre varchar(255) NOT NULL,
    codigo varchar(32) NULL,
    marca varchar(120) NULL,
    modelo varchar(120) NULL,
    pais char(2) NOT NULL DEFAULT 'MX',
    ubicacion_texto varchar(255) NULL,
    tipo_conexion varchar(20) NOT NULL,
    modo_envio varchar(20) NOT NULL,
    host_ip varchar(255) NULL,
    puerto integer NULL,
    cola_nombre varchar(255) NULL,
    nombre_sistema varchar(255) NULL,
    id_agente varchar(255) NULL,
    usa_tls boolean NOT NULL DEFAULT false,
    tamano_papel varchar(20) NOT NULL DEFAULT 'letter',
    orientacion varchar(20) NOT NULL DEFAULT 'portrait',
    duplex varchar(20) NOT NULL DEFAULT 'none',
    color_modo varchar(20) NOT NULL DEFAULT 'mono',
    bandeja varchar(120) NULL,
    copias_default integer NOT NULL DEFAULT 1,
    notas text NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_impresora_tipo_conexion
        CHECK (tipo_conexion IN ('wifi', 'ethernet', 'usb', 'bluetooth')),
    CONSTRAINT ck_impresora_modo_envio
        CHECK (modo_envio IN ('sistema_local', 'ipp', 'raw_9100', 'agente')),
    CONSTRAINT ck_impresora_pais
        CHECK (pais IN ('CO', 'MX', 'US')),
    CONSTRAINT ck_impresora_tamano_papel
        CHECK (tamano_papel IN ('letter', 'legal', 'a4')),
    CONSTRAINT ck_impresora_orientacion
        CHECK (orientacion IN ('portrait', 'landscape')),
    CONSTRAINT ck_impresora_duplex
        CHECK (duplex IN ('none', 'long_edge', 'short_edge')),
    CONSTRAINT ck_impresora_color
        CHECK (color_modo IN ('mono', 'color')),
    CONSTRAINT ck_impresora_copias
        CHECK (copias_default >= 1 AND copias_default <= 99)
);

COMMENT ON TABLE public.impresora IS
    'Configuración de impresoras carta (Letter) para Polaria WMS (Wi‑Fi/cable/USB vía agente).';
COMMENT ON COLUMN public.impresora.modo_envio IS
    'sistema_local: nombre OS; ipp: IPP/IPPS; raw_9100: JetDirect; agente: QZ Tray/PrintNode.';
COMMENT ON COLUMN public.impresora.tamano_papel IS
    'Por defecto letter (8.5×11 in). Usado en CO/MX/US para documentos carta.';

CREATE INDEX IF NOT EXISTS idx_impresora_cuenta
    ON public.impresora (codigo_cuenta)
    WHERE esta_activa;

CREATE INDEX IF NOT EXISTS idx_impresora_bodega
    ON public.impresora (id_bodega)
    WHERE id_bodega IS NOT NULL AND esta_activa;

ALTER TABLE public.impresora ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'impresora'
          AND policyname = 'impresora_select_authenticated'
    ) THEN
        CREATE POLICY impresora_select_authenticated
            ON public.impresora
            FOR SELECT
            TO authenticated
            USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'impresora'
          AND policyname = 'impresora_write_authenticated'
    ) THEN
        CREATE POLICY impresora_write_authenticated
            ON public.impresora
            FOR ALL
            TO authenticated
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
