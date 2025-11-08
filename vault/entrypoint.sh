#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

mkdir -p /vault/logs

log "[INIT] Installing PostgreSQL client tools..."
if command -v apk >/dev/null 2>&1; then
  log "[INIT] Installing PostgreSQL client and curl (Alpine)..."
  apk add --no-cache postgresql-client curl
elif command -v apt-get >/dev/null 2>&1; then
  log "[INIT] Installing PostgreSQL client and curl (Debian/Ubuntu)..."
  apt-get update -qq && apt-get install -y -qq postgresql-client curl && rm -rf /var/lib/apt/lists/*
else
  log "ERROR: Unknown base image (no apk or apt-get found)"
  exit 1
fi


TEMPLATE=/vault/config/config.hcl
OUT=/vault/config.generated.hcl

log "Starting Vault entrypoint..."

# Load secrets
if [ -f /run/secrets/db_password ]; then
  DB_PASS=$(cat /run/secrets/db_password)
else
  log "ERROR: /run/secrets/db_password not found"
  exit 1
fi

# Prefer explicit connection URL secret if provided
if [ -f /run/secrets/vault_connection_url ]; then
  VAULT_CONNECTION_URL=$(cat /run/secrets/vault_connection_url)
  log "Using Vault DB connection URL from secret $VAULT_CONNECTION_URL"
else
  VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@postgres:5432/vaultdb?sslmode=disable"
fi

export PGPASSWORD="$DB_PASS"
export VAULT_CONNECTION_URL="$VAULT_CONNECTION_URL"

log "Using Vault DB connection: $VAULT_CONNECTION_URL"

# Ensure template exists
if [ ! -f "$TEMPLATE" ]; then
  log "ERROR: template $TEMPLATE not found"
  exit 1
fi

# Generate config
if command -v envsubst >/dev/null 2>&1; then
  log "Generating $OUT using envsubst"
  envsubst < "$TEMPLATE" > "$OUT" || { log "ERROR: envsubst failed"; exit 1; }
else
  log "envsubst not found, using sed fallback"
  sed "s|@VAULT_CONNECTION_URL@|$VAULT_CONNECTION_URL|g; \
       s|\${VAULT_CONNECTION_URL}|$VAULT_CONNECTION_URL|g; \
       s|{{VAULT_CONNECTION_URL}}|$VAULT_CONNECTION_URL|g" \
       "$TEMPLATE" > "$OUT"
fi

log "Generated $OUT (size=$(stat -c%s "$OUT" 2>/dev/null || echo unknown))"

# Copy unseal script
if [ -f /vault/unseal.sh ]; then
  cp /vault/unseal.sh /tmp/unseal.sh
  chmod +x /tmp/unseal.sh
else
  log "Warning: /vault/unseal.sh not found"
fi

log "Waiting for Postgres to become ready..."
for i in $(seq 1 30); do
  if pg_isready -h postgres -p 5432 -U vault_app >/dev/null 2>&1; then
    log "Postgres is ready!"
    break
  fi
  sleep 2
done


# Launch Vault in background and stream logs
log "Launching Vault with $OUT"
vault server -config="$OUT"
VAULT_PID=$!

# Graceful shutdown
trap "log 'Caught SIGTERM, shutting down Vault...'; kill $VAULT_PID 2>/dev/null || true; exit 0" TERM INT

# Auto-unseal
if [ -f /tmp/unseal.sh ]; then
    log "Running auto-unseal script"
    /tmp/unseal.sh
fi

# Wait until Vault is healthy
HEALTH_URL="http://127.0.0.1:8200/v1/sys/health"
MAX_HEALTH_WAIT=180
HEALTH_WAITED=0
while ! curl -s "$HEALTH_URL" >/dev/null 2>&1; do
    sleep 2
    HEALTH_WAITED=$((WAITED + 2))
    if [ "HEALTH_WAITED" -ge "MAX_HEALTH_WAIT" ]; then
        log "Vault health check timed out"
        exit 1
    fi
done
log "Vault is up and unsealed!"

# Tail logs or wait for Vault
tail -f /vault/logs/vault.log &
wait $VAULT_PID

log "Vault ready and unsealed. PID=$VAULT_PID"

wait $VAULT_PID
