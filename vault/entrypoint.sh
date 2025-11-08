#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

TEMPLATE=/vault/config/config.hcl
OUT=/vault/config.generated.hcl

log "TEMPLATE: $(cat $TEMPLATE)"

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
  log "ERROR: template $TEMPLATE not found. Cannot generate $OUT"
  exit 1
fi

# Generate config: prefer envsubst, fallback to sed replacements
if command -v envsubst >/dev/null 2>&1; then
  log "Generating $OUT using envsubst"
  envsubst < "$TEMPLATE" > "$OUT" || { log "ERROR: envsubst failed"; exit 1; }
else
  log "envsubst not found, using sed fallback for VAULT_CONNECTION_URL"
  sed "s|@VAULT_CONNECTION_URL@|$VAULT_CONNECTION_URL|g; s|\\\${VAULT_CONNECTION_URL}|$VAULT_CONNECTION_URL|g; s|{{VAULT_CONNECTION_URL}}|$VAULT_CONNECTION_URL|g" "$TEMPLATE" > "$OUT" || { log "ERROR: sed replacement failed"; exit 1; }
fi

if [ ! -s "$OUT" ]; then
  log "ERROR: generated file $OUT is empty"
  exit 1
fi

log "Generated $OUT (size=$(stat -c%s "$OUT" 2>/dev/null || echo unknown))"

# Optionally copy unseal/init script if provided
if [ -f /vault/unseal.sh ]; then
  cp /vault/unseal.sh /tmp/unseal.sh 2>/dev/null || true
  chmod +x /tmp/unseal.sh 2>/dev/null || true
else
  log "Warning: /vault/unseal.sh not found"
fi

# Wait for Postgres
wait_for_pg() {
  HOST=infra_postgres
  PORT=5432
  USER=vault_app
  MAX_WAIT=60
  WAITED=0

  if command -v pg_isready >/dev/null 2>&1; then
    log "Using pg_isready to wait for Postgres"
    until PGPASSWORD="$DB_PASS" pg_isready -h "$HOST" -p "$PORT" -U "$USER" >/dev/null 2>&1; do
      sleep 2
      WAITED=$((WAITED + 2))
      if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        return 1
      fi
    done
    return 0
  fi

  if command -v nc >/dev/null 2>&1; then
    log "pg_isready not found; using nc TCP probe"
    until nc -z "$HOST" "$PORT" >/dev/null 2>&1; do
      sleep 2
      WAITED=$((WAITED + 2))
      if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        return 1
      fi
    done
    return 0
  fi

  log "pg_isready and nc not available; using /dev/tcp probe"
  until timeout 1 sh -c "cat < /dev/null > /dev/tcp/$HOST/$PORT" >/dev/null 2>&1; do
    sleep 2
    WAITED=$((WAITED + 2))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
      return 1
    fi
  done
  return 0
}

log "Waiting for Postgres to be ready..."
if ! wait_for_pg; then
  log "Postgres not ready after timeout, exiting."
  exit 1
fi

# Start Vault using the generated config
log "Launching Vault with $OUT"
vault server -config="$OUT" &
VAULT_PID=$!

trap "log 'Caught SIGTERM, shutting down Vault...'; kill $VAULT_PID 2>/dev/null || true; exit 0" TERM INT

log "Waiting for Vault to become healthy (handles init/unseal)..."

MAX_HEALTH_WAIT=120
HEALTH_WAITED=0
HEALTH_SLEEP=2

vault_health_code() {
  HEALTH_URL="http://localhost:8200/v1/sys/health"

  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    # wget prints server response to stderr; capture and parse the HTTP status code
    status=$(wget --server-response --spider "$HEALTH_URL" 2>&1 | awk '/HTTP\// {print $2; exit}')
    if [ -z "$status" ]; then
      echo "000"
    else
      echo "$status"
    fi
    return
  fi

  if command -v nc >/dev/null 2>&1; then
    # send minimal HTTP/1.0 request and parse the status code from the first line
    status=$(printf 'GET /v1/sys/health HTTP/1.0\r\nHost: localhost\r\n\r\n' | nc -w 2 localhost 8200 2>/dev/null | head -n1 | awk '{print $2}')
    if [ -z "$status" ]; then
      echo "000"
    else
      echo "$status"
    fi
    return
  fi

  # no HTTP tool available
  echo "000"
}

while :; do
  status=$(vault_health_code)
  log "Vault health status: $status"

  case "$status" in
    200)
      log "Vault is initialized, unsealed and active."
      break
      ;;
    429)
      log "Vault is standby (429). If running in HA, this node is standby; waiting..."
      ;;
    503)
      log "Vault is sealed (503). Attempting to run unseal script if available..."
      if [ -f /tmp/unseal.sh ]; then
        /tmp/unseal.sh || log "Warning: unseal script returned non-zero"
      else
        log "No unseal script found at /tmp/unseal.sh"
      fi
      ;;
    501)
      log "Vault not initialized (501). Attempting initialization via unseal script if available..."
      if [ -f /tmp/unseal.sh ]; then
        /tmp/unseal.sh || log "Warning: init/unseal script returned non-zero"
      else
        log "No init/unseal script found at /tmp/unseal.sh"
      fi
      ;;
    000)
      log "Vault health endpoint not reachable yet."
      ;;
    *)
      log "Vault returned unexpected health code: $status"
      ;;
  esac

  sleep "$HEALTH_SLEEP"
  HEALTH_WAITED=$((HEALTH_WAITED + HEALTH_SLEEP))
  if [ "$HEALTH_WAITED" -ge "$MAX_HEALTH_WAIT" ]; then
    log "Timed out waiting for Vault health ($MAX_HEALTH_WAIT s). Exiting."
    exit 1
  fi
done

log "Vault ready and unsealed. PID=$VAULT_PID"

wait $VAULT_PID
