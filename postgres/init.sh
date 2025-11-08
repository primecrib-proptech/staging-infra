#!/bin/sh
set -eu

# Path to docker secret (override with DB_PASSWORD_FILE env if needed)
SECRET_FILE=${DB_PASSWORD_FILE:-/run/secrets/db_password}
TEMPLATE=${INIT_SQL_TEMPLATE:-/docker-entrypoint-initdb.d/init.sql.template}
OUT_SQL=/tmp/init-generated.sql

err() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f "$SECRET_FILE" ] || err "DB password secret not found at $SECRET_FILE"
[ -f "$TEMPLATE" ] || err "SQL template not found at $TEMPLATE"

# Read and double single quotes for safe SQL literal (SQL uses '' to escape ')
DB_PW_RAW=$(sed "s/'/''/g" "$SECRET_FILE")

# Escape sed-special chars so substitution is safe
DB_PW_ESC=$(printf '%s' "$DB_PW_RAW" | sed -e 's/[\/&]/\\&/g')

# Generate SQL with substituted password placeholder
sed "s/@DB_PASSWORD@/$DB_PW_ESC/g" "$TEMPLATE" > "$OUT_SQL"

# Execute generated SQL as the Postgres superuser provided by the image
# The official image runs init scripts as the 'postgres' user so this should work.
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-postgres}" -f "$OUT_SQL"

# cleanup (optional)
rm -f "$OUT_SQL" || true