#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

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
else
  VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@infra_postgres:5432/vaultdb?sslmode=disable"
fi

export PGPASSWORD="$DB_PASS"
export VAULT_CONNECTION_URL

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
#  sed "s|@VAULT_CONNECTION_URL@|$VAULT_CONNECTION_URL|g" "$TEMPLATE" > "$OUT" || { log "ERROR: sed replacement failed"; exit 1; }
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

# Wait for Postgres
wait_for_pg() {
  HOST=infra_postgres
  PORT=5432
  USER=vault_app
  MAX_WAIT=120
  WAITED=0

  log "Waiting for Postgres at $HOST:$PORT..."
  until PGPASSWORD="$DB_PASS" pg_isready -h "$HOST" -p "$PORT" -U "$USER" >/dev/null 2>&1; do
    sleep 2
    WAITED=$((WAITED + 2))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
      log "Postgres not ready after $MAX_WAIT seconds"
      return 1
    fi
  done
  log "Postgres is ready"
  return 0
}

if ! wait_for_pg; then
  exit 1
fi

# Launch Vault in background and stream logs
log "Launching Vault with $OUT"
vault server -config="$OUT"
#vault server -config="$OUT" > /vault/logs/vault.log 2>&1 &
#VAULT_PID=$!

# Auto-unseal
if [ -f /tmp/unseal.sh ]; then
  log "Running auto-unseal script"
  /tmp/unseal.sh
fi

# Graceful shutdown
trap "log 'Caught SIGTERM, shutting down Vault...'; kill $VAULT_PID 2>/dev/null || true; exit 0" TERM INT

# Stream logs in background
#exec vault server -config="$OUT"
#tail -f /vault/logs/vault.log &
TAIL_PID=$!

# Health check loop
HEALTH_URL="http://127.0.0.1:8200/v1/sys/health"
MAX_HEALTH_WAIT=180
HEALTH_WAITED=0

log "Waiting for Vault to become healthy..."
while :; do
  if command -v curl >/dev/null 2>&1; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
  else
    STATUS="000"
  fi

  log "Vault health status: $STATUS"

  case "$STATUS" in
    200)
      log "Vault is initialized, unsealed, and active"
      break
      ;;
    429)
      log "Vault is standby (HA)"
      ;;
    503|501)
      log "Vault sealed or not initialized, attempting unseal/init"
      if [ -f /tmp/unseal.sh ]; then
        /tmp/unseal.sh || log "Warning: unseal/init script failed"
      else
        log "No unseal script found at /tmp/unseal.sh"
      fi
      ;;
    000)
      log "Vault health endpoint not reachable yet"
      ;;
    *)
      log "Unexpected health code: $STATUS"
      ;;
  esac

  sleep 2
  HEALTH_WAITED=$((HEALTH_WAITED + 2))
  if [ "$HEALTH_WAITED" -ge "$MAX_HEALTH_WAIT" ]; then
    log "Timed out waiting for Vault health ($MAX_HEALTH_WAIT s)"
    exit 1
  fi
done

log "Vault ready and unsealed. PID=$VAULT_PID"

wait $VAULT_PID
