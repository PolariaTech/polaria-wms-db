-- REQ-370: la OV debe mostrar los productos en el mismo orden en que vienen en la OC.
--
-- Hoy `orden_venta_linea` no guarda ningún orden: la web las lee de Supabase sin ORDER BY y la API
-- las ordena por `id_linea_orden_venta`, que es un UUID aleatorio. Por eso una OC con LIMÓN y luego
-- PIÑA se ve en la OV con PIÑA primero.
--
-- Solución: una columna `posicion` (0, 1, 2, ...) con el lugar de cada línea en la OC. La web la
-- escribe al insertar las líneas y la web y la API ordenan por ella.
--
-- La columna nace en NULL y sin default: las líneas que ya existen no tienen un orden que
-- recuperar, y quien las lee las deja al final, en el orden de antes (`NULLS LAST`).
-- Idempotente: seguro de correr más de una vez.

ALTER TABLE public.orden_venta_linea
    ADD COLUMN IF NOT EXISTS posicion integer;

COMMENT ON COLUMN public.orden_venta_linea.posicion IS
    'Lugar de la línea en la OC de origen (0, 1, 2, ...). NULL = línea anterior a REQ-370, sin orden guardado. Quien lee ordena por esta columna con NULLS LAST.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta_linea', 'posicion');
    END IF;
END $$;

-- wms_sync_column_to_tenants no copia CHECK: se agrega aquí, en public y en cada esquema.
-- Los esquemas se toman de pg_namespace (como la migración 123) y la columna se asegura en cada
-- uno, así la migración no depende de que la función de sincronización exista.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name
        FROM pg_namespace n
        WHERE n.nspname = 'public'
           OR n.nspname = 'template_wms'
           OR n.nspname LIKE 'emp\_%'
    LOOP
        IF to_regclass(format('%I.orden_venta_linea', r.schema_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format(
            'ALTER TABLE %I.orden_venta_linea ADD COLUMN IF NOT EXISTS posicion integer',
            r.schema_name
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint c
            WHERE c.conname = 'chk_orden_venta_linea_posicion_no_negativa'
              AND c.conrelid = format('%I.orden_venta_linea', r.schema_name)::regclass
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.orden_venta_linea ADD CONSTRAINT chk_orden_venta_linea_posicion_no_negativa CHECK (posicion IS NULL OR posicion >= 0)',
                r.schema_name
            );
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
