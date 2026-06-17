#!/bin/sh
set -eu

read_secret() {
  file="$1"

  if [ ! -f "$file" ]; then
    echo "Missing secret: $file"
    exit 1
  fi

  cat "$file"
}

export DB_OWNER_PASSWORD=$(read_secret /run/secrets/db_password)
export DB_RO_PASSWORD=$(read_secret /run/secrets/db_ro_password)
export DB_APP_PASSWORD=$(read_secret /run/secrets/db_app_password)
export DB_API_PASSWORD=$(read_secret /run/secrets/db_api_password)
export DB_MIGRATION_PASSWORD=$(read_secret /run/secrets/db_migration_password)

until pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 2
done

psql -U postgres -d postgres \
    -v DB_OWNER_PASSWORD="$DB_OWNER_PASSWORD" \
    -v DB_RO_PASSWORD="$DB_RO_PASSWORD" \
    -v DB_APP_PASSWORD="$DB_APP_PASSWORD" \
    -v DB_API_PASSWORD="$DB_API_PASSWORD" \
    -v DB_MIGRATION_PASSWORD="$DB_MIGRATION_PASSWORD" \
    -f /docker-entrypoint-initdb.d/init.sql.template
