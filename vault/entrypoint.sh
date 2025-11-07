#!/bin/sh
set -e

echo "[Vault Entrypoint] Starting setup..."

DB_PASS=$(cat /run/secrets/db_password)
VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@postgres:5432/vaultdb?sslmode=disable"
export VAULT_CONNECTION_URL

echo "[Vault Entrypoint] Using Vault DB connection: $VAULT_CONNECTION_URL"

# Install gettext for envsubst if not available
if command -v apk >/dev/null 2>&1; then
  apk add --no-cache gettext >/dev/null 2>&1 || true
fi

# Substitute variables into config
envsubst < /vault/config/config.hcl > /vault/config/config.generated.hcl

# Graceful shutdown handler
trap "echo '[Vault Entrypoint] Caught SIGTERM, shutting down Vault...'; pkill vault; exit 0" TERM INT

echo "[Vault Entrypoint] Launching Vault..."
vault server -config=/vault/config/config.generated.hcl &

VAULT_PID=$!

# Wait for Vault to start
sleep 10

echo "[Vault Entrypoint] Running unseal script..."
/vault/unseal.sh

echo "[Vault Entrypoint] Vault ready and unsealed. PID=$VAULT_PID"

# Keep the container alive
wait $VAULT_PID
