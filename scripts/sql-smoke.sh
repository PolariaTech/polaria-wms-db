#!/usr/bin/env bash
# Misma secuencia que .github/workflows/ci.yml. Con PGHOST usa el Postgres ya
# levantado (el servicio de GitHub Actions). Sin PGHOST levanta un contenedor
# efímero y lo borra al salir.
set -euo pipefail

raiz="$(cd "$(dirname "$0")/.." && pwd)"
cd "$raiz"

contenedor=""
prefijo="."

limpiar() {
  if [[ -n "$contenedor" ]]; then
    docker rm -f "$contenedor" >/dev/null 2>&1 || true
  fi
}
trap limpiar EXIT

if [[ -z "${PGHOST:-}" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "No hay PGHOST ni docker. No se puede correr el humo SQL." >&2
    exit 1
  fi
  contenedor="polaria-sql-smoke-$$"
  docker run -d --name "$contenedor" \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=polaria \
    -v "$raiz:/work:ro" \
    postgres:16-alpine >/dev/null
  prefijo="/work"
  listo=0
  for _ in $(seq 1 40); do
    if docker exec "$contenedor" pg_isready -U postgres -d polaria >/dev/null 2>&1; then
      listo=1
      break
    fi
    sleep 1
  done
  if [[ "$listo" != 1 ]]; then
    echo "Postgres del humo no quedó listo." >&2
    exit 1
  fi
elif ! command -v psql >/dev/null 2>&1; then
  echo "PGHOST está definido y no hay psql en el PATH." >&2
  exit 1
fi

sql() {
  if [[ -n "$contenedor" ]]; then
    docker exec -e PGPASSWORD=postgres "$contenedor" \
      psql -v ON_ERROR_STOP=1 -U postgres -d polaria "$@"
  else
    psql -v ON_ERROR_STOP=1 "$@"
  fi
}

sql -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
sql -f "$prefijo/scripts/bootstrap-auth.sql"
sql -c "SELECT auth.uid() IS NULL AS ok;"
sql -c "DO \$\$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;"
sql -c "DO \$\$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;"
sql -c "CREATE TABLE IF NOT EXISTS public.mateo_handoff_jti (id uuid PRIMARY KEY);"
sql -c "CREATE TABLE IF NOT EXISTS public.rate_limit_bucket (id uuid PRIMARY KEY);"
sql -f "$prefijo/migrations/121_mateo_handoff_jti_rate_limit_bucket_rls.sql"
sql -f "$prefijo/supabase/tests/121_mateo_handoff_jti_rate_limit_bucket_rls_test.sql"

# Migración 112: enum estado_orden_venta con revisada y facturada.
sql -c "DO \$\$ BEGIN CREATE TYPE public.estado_orden_venta AS ENUM ('por_confirmar', 'confirmada', 'alistamiento', 'alistada', 'despachada', 'cancelada'); EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;"
sql -f "$prefijo/migrations/112_estado_orden_venta_revisada_facturada.sql"
# Segunda corrida: la migración debe ser idempotente.
sql -f "$prefijo/migrations/112_estado_orden_venta_revisada_facturada.sql"
sql -f "$prefijo/supabase/tests/112_estado_orden_venta_revisada_facturada_test.sql"

# Migración 122: tablas mínimas con solo la llave, porque la migración agrega las columnas.
# public.empresa vacía: no hay schemas emp_*, así que la prueba recorre solo public.
sql -c "CREATE TABLE IF NOT EXISTS public.empresa (schema_name text);"
sql -c "CREATE TABLE IF NOT EXISTS public.orden_venta (id_orden_venta uuid PRIMARY KEY, estado text, notas text);"
sql -c "CREATE TABLE IF NOT EXISTS public.orden_venta_linea (id_orden_venta_linea uuid PRIMARY KEY);"
sql -c "CREATE TABLE IF NOT EXISTS public.orden_trabajo (id_orden_trabajo uuid PRIMARY KEY);"
sql -f "$prefijo/migrations/122_orden_venta_linea_precio_y_ot_id_orden_venta.sql"
# Segunda corrida: la migración debe ser idempotente.
sql -f "$prefijo/migrations/122_orden_venta_linea_precio_y_ot_id_orden_venta.sql"
sql -f "$prefijo/supabase/tests/122_orden_venta_linea_precio_y_ot_id_orden_venta_test.sql"

# Migración 123: authenticated no cambia orden_venta.estado; solo la API Nest (postgres).
# Un tenant mínimo (emp_smoke) para probar el bucle de tenants de la migración.
sql -c "CREATE SCHEMA IF NOT EXISTS emp_smoke;"
sql -c "CREATE TABLE IF NOT EXISTS emp_smoke.orden_venta (id_orden_venta uuid PRIMARY KEY, estado text, notas text);"
sql -f "$prefijo/migrations/123_ov_estado_solo_api_nest.sql"
# Segunda corrida: la migración debe ser idempotente.
sql -f "$prefijo/migrations/123_ov_estado_solo_api_nest.sql"
sql -f "$prefijo/supabase/tests/123_ov_estado_solo_api_nest_test.sql"

# Migración 124: orden_venta_linea.posicion guarda el orden de la OC (REQ-370).
sql -c "CREATE TABLE IF NOT EXISTS emp_smoke.orden_venta_linea (id_orden_venta_linea uuid PRIMARY KEY);"
sql -f "$prefijo/migrations/124_orden_venta_linea_posicion.sql"
# Segunda corrida: la migración debe ser idempotente.
sql -f "$prefijo/migrations/124_orden_venta_linea_posicion.sql"
sql -f "$prefijo/supabase/tests/124_orden_venta_linea_posicion_test.sql"

echo "SQL_SMOKE_OK"
