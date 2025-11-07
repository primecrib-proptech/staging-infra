#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting Vault setup..."

DB_PASS=$(cat /run/secrets/db_password)
VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@45.130.104.193:5432/vaultdb?sslmode=disable"
export VAULT_CONNECTION_URL
log "Using Vault DB connection: $VAULT_CONNECTION_URL"

if command -v apk >/dev/null 2>&1; then
  apk add --no-cache gettext >/dev/null 2>&1 || true
fi

envsubst < /vault/config/config.hcl > /vault/config/config.generated.hcl

# Optional: copy unseal script if read-only
cp /vault/unseal.sh /tmp/unseal.sh
chmod +x /tmp/unseal.sh

trap "log 'Caught SIGTERM, shutting down Vault...'; kill $VAULT_PID; exit 0" TERM INT

log "Waiting for Postgres to be ready..."
until pg_isready -h postgres -p 5432 -U vault_app >/dev/null 2>&1; do
    log "Postgres not ready, retrying..."
    sleep 2
done

log "Launching Vault..."
vault server -config=/vault/config/config.generated.hcl &
VAULT_PID=$!

log "Waiting for Vault to be ready..."
until curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1; do
    sleep 1
done

log "Running unseal script..."
/tmp/unseal.sh

log "Vault ready and unsealed. PID=$VAULT_PID"

wait $VAULT_PID
