#!/bin/sh
set -e

DB_PASS=`cat /run/secrets/db_password`
VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@postgres:5432/vaultdb?sslmode=disable"
export VAULT_CONNECTION_URL

if command -v apk >/dev/null 2>&1; then
  apk add --no-cache gettext >/dev/null 2>&1 || true
fi

envsubst < /vault/config/config.hcl > /vault/config/config.generated.hcl
vault server -config=/vault/config/config.generated.hcl &
sleep 10
/vault/unseal.sh
tail -f /dev/null
