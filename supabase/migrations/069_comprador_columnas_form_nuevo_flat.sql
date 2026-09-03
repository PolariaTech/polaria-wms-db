-- Columnas planas del formulario nuevo de comprador (sin depender de JSON).
-- Complementa 068_comprador_metadatos_alta.

ALTER TABLE public.comprador
    ADD COLUMN IF NOT EXISTS razon_social text,
    ADD COLUMN IF NOT EXISTS rfc text,
    ADD COLUMN IF NOT EXISTS regimen text,
    ADD COLUMN IF NOT EXISTS cp_fiscal text,
    ADD COLUMN IF NOT EXISTS uso_cfdi text,
    ADD COLUMN IF NOT EXISTS constancia_nombre text,
    ADD COLUMN IF NOT EXISTS constancia_fecha text,
    ADD COLUMN IF NOT EXISTS apodo text,
    ADD COLUMN IF NOT EXISTS grupo text,
    ADD COLUMN IF NOT EXISTS vendedor text,
    ADD COLUMN IF NOT EXISTS estado text,
    ADD COLUMN IF NOT EXISTS lista_precios text,
    ADD COLUMN IF NOT EXISTS dias_credito text,
    ADD COLUMN IF NOT EXISTS limite_credito text,
    ADD COLUMN IF NOT EXISTS metodo_pago text,
    ADD COLUMN IF NOT EXISTS forma_pago text,
    ADD COLUMN IF NOT EXISTS moneda text,
    ADD COLUMN IF NOT EXISTS exige_oc text,
    ADD COLUMN IF NOT EXISTS correos_cfdi text,
    ADD COLUMN IF NOT EXISTS complemento_pago boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS whatsapp text,
    ADD COLUMN IF NOT EXISTS formato_pedido text,
    ADD COLUMN IF NOT EXISTS correos_pedido text,
    ADD COLUMN IF NOT EXISTS portal_proveedores boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS portal_nota text,
    ADD COLUMN IF NOT EXISTS sustituciones text,
    ADD COLUMN IF NOT EXISTS tolerancia text,
    ADD COLUMN IF NOT EXISTS vida_util text,
    ADD COLUMN IF NOT EXISTS requiere_lote text,
    ADD COLUMN IF NOT EXISTS requiere_temp text,
    ADD COLUMN IF NOT EXISTS requiere_ficha text,
    ADD COLUMN IF NOT EXISTS politica_devolucion text,
    -- Primer centro de consumo / entrega
    ADD COLUMN IF NOT EXISTS centro_nombre text,
    ADD COLUMN IF NOT EXISTS centro_dias text,
    ADD COLUMN IF NOT EXISTS centro_direccion text,
    ADD COLUMN IF NOT EXISTS centro_cp text,
    ADD COLUMN IF NOT EXISTS centro_anden text,
    ADD COLUMN IF NOT EXISTS centro_desde text,
    ADD COLUMN IF NOT EXISTS centro_hasta text,
    ADD COLUMN IF NOT EXISTS centro_contacto text,
    ADD COLUMN IF NOT EXISTS centro_telefono text,
    ADD COLUMN IF NOT EXISTS centro_carretera_federal text,
    ADD COLUMN IF NOT EXISTS centro_notas text,
    -- Primer contacto
    ADD COLUMN IF NOT EXISTS contacto_nombre text,
    ADD COLUMN IF NOT EXISTS contacto_puesto text,
    ADD COLUMN IF NOT EXISTS contacto_rol text,
    ADD COLUMN IF NOT EXISTS contacto_telefono text,
    ADD COLUMN IF NOT EXISTS contacto_correo text;

COMMENT ON COLUMN public.comprador.razon_social IS
    'Razón social fiscal del comprador (formulario de alta).';
COMMENT ON COLUMN public.comprador.centro_nombre IS
    'Nombre del primer centro de consumo / entrega.';
COMMENT ON COLUMN public.comprador.contacto_nombre IS
    'Nombre del primer contacto operativo.';

DO $$
DECLARE
    col text;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        FOREACH col IN ARRAY ARRAY[
            'razon_social','rfc','regimen','cp_fiscal','uso_cfdi',
            'constancia_nombre','constancia_fecha','apodo','grupo','vendedor','estado',
            'lista_precios','dias_credito','limite_credito','metodo_pago','forma_pago',
            'moneda','exige_oc','correos_cfdi','complemento_pago','whatsapp','formato_pedido',
            'correos_pedido','portal_proveedores','portal_nota','sustituciones','tolerancia',
            'vida_util','requiere_lote','requiere_temp','requiere_ficha','politica_devolucion',
            'centro_nombre','centro_dias','centro_direccion','centro_cp','centro_anden',
            'centro_desde','centro_hasta','centro_contacto','centro_telefono',
            'centro_carretera_federal','centro_notas',
            'contacto_nombre','contacto_puesto','contacto_rol','contacto_telefono','contacto_correo'
        ]
        LOOP
            PERFORM public.wms_sync_column_to_tenants('comprador', col);
        END LOOP;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
