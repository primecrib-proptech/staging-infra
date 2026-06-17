#!/bin/sh
set -eu

export DB_PASSWORD=$(cat /run/secrets/db_password) #DB Owner password
export DB_RO_PASSWORD=$(cat /run/secrets/db_ro_password)
export DB_APP_PASSWORD=$(cat /run/secrets/db_app_password)
export DB_API_PASSWORD=$(cat /run/secrets/db_api_password)
export DB_MIGRATION_PASSWORD=$(cat /run/secrets/db_migration_password)

# Wait for PostgreSQL to be ready
until pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 2
done

# Run the SQL initialization template with variable substitution
psql -v DB_PASSWORD="$DB_PASSWORD" \
     -f /docker-entrypoint-initdb.d/init.sql.template


## Run the SQL initialization template with variable substitution
 #psql -U postgres -v PROPTECH_PASSWORD="$PROPTECH_PASSWORD" \
 #     -v AUDIT_PASSWORD="$AUDIT_PASSWORD" \
 #     -v VAULT_PASSWORD="$VAULT_PASSWORD" \
 #     -v QUARTZ_PASSWORD="$QUARTZ_PASSWORD" \
 #     -f /docker-entrypoint-initdb.d/init.sql.template
