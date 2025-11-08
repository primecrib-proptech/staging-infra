#!/bin/sh
set -eu

export DB_PASSWORD=$(cat /run/secrets/db_password)

psql -v DB_PASSWORD="$DB_PASSWORD" \
     -f /docker-entrypoint-initdb.d/init.sql.template
