-- Caminos de impresión: QZ (existente), Brother email-to-print, Epson Connect.
-- email_destino: correo de la impresora (Brother Apps / Epson Connect).

ALTER TABLE public.impresora
    DROP CONSTRAINT IF EXISTS ck_impresora_modo_envio;

ALTER TABLE public.impresora
    ADD CONSTRAINT ck_impresora_modo_envio
        CHECK (modo_envio IN (
            'sistema_local',
            'ipp',
            'raw_9100',
            'agente',
            'email',
            'epson_connect'
        ));

ALTER TABLE public.impresora
    ADD COLUMN IF NOT EXISTS email_destino varchar(320) NULL;

COMMENT ON COLUMN public.impresora.modo_envio IS
    'sistema_local/ipp/raw_9100/agente: LAN o QZ Tray; email: Brother email-to-print; epson_connect: Epson Connect API.';
COMMENT ON COLUMN public.impresora.email_destino IS
    'Correo de la impresora (Brother Attach/Email Print o Epson Connect Remote Print).';

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
