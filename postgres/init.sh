#!/bin/sh
set -eu

export DB_PASSWORD=$(cat /run/secrets/db_password)

# Wait for PostgreSQL to be ready
until pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 2
done

psql -v DB_PASSWORD="$DB_PASSWORD" \
     -f /docker-entrypoint-initdb.d/init.sql.template
