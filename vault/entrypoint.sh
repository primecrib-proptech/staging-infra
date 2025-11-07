#!/bin/sh
set -e

echo "[Vault Entrypoint] Starting setup..."

# Load DB password from secret
DB_PASS=$(cat /run/secrets/db_password)
VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@infra_postgres:5432/vaultdb?sslmode=disable"
export VAULT_CONNECTION_URL

echo "[Vault Entrypoint] Using Vault DB connection: $VAULT_CONNECTION_URL"

# Install gettext for envsubst if not available
if command -v apk >/dev/null 2>&1; then
  apk add --no-cache gettext >/dev/null 2>&1 || true
fi

# Substitute variables into config
envsubst < /vault/config/config.hcl > /vault/config/config.generated.hcl

# Make unseal script executable
chmod +x /vault/unseal.sh

# Graceful shutdown handler
trap "echo '[Vault Entrypoint] Caught SIGTERM, shutting down Vault...'; pkill vault; exit 0" TERM INT

echo "[Vault Entrypoint] Launching Vault..."
vault server -config=/vault/config/config.generated.hcl &

VAULT_PID=$!

# Wait for Vault to become ready
echo "[Vault Entrypoint] Waiting for Vault to be ready..."
until curl -s http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; do
    sleep 1
done

echo "[Vault Entrypoint] Running unseal script..."
/vault/unseal.sh

echo "[Vault Entrypoint] Vault ready and unsealed. PID=$VAULT_PID"

# Keep container alive
wait $VAULT_PID
