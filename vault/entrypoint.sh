#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

TEMPLATE=/vault/config/config.hcl
OUT=/vault/config.generated.hcl
mkdir -p /vault/logs

log "Starting Vault entrypoint..."

# Ensure basic tools or attempt install if running as root
ensure_tool() {
  cmd=$1
  pkg=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if [ "$(id -u)" -ne 0 ]; then
    log "Warning: $cmd missing and not running as root; continuing without it"
    return 1
  fi
  if command -v apk >/dev/null 2>&1 && [ -n "$pkg" ]; then
    log "Installing $pkg (Alpine)"
    apk add --no-cache "$pkg"
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1 && [ -n "$pkg" ]; then
    log "Installing $pkg (Debian/Ubuntu)"
    apt-get update -qq && apt-get install -y -qq "$pkg" && rm -rf /var/lib/apt/lists/*
    return 0
  fi
  log "Could not install $cmd (no supported package manager)"
  return 1
}

# Ensure common helpers (best: include them in the image)
ensure_tool curl curl >/dev/null 2>&1 || true
ensure_tool wget wget >/dev/null 2>&1 || true
ensure_tool nc netcat-openbsd >/dev/null 2>&1 || true
ensure_tool pg_isready postgresql-client >/dev/null 2>&1 || true
ensure_tool envsubst gettext-base >/dev/null 2>&1 || true

# Load DB password secret (support Docker secrets path)
if [ -n "${VAULT_POSTGRES_PASSWORD_FILE:-}" ] && [ -f "$VAULT_POSTGRES_PASSWORD_FILE" ]; then
  DB_PASS=$(cat "$VAULT_POSTGRES_PASSWORD_FILE")
elif [ -f /run/secrets/db_password ]; then
  DB_PASS=$(cat /run/secrets/db_password)
else
  log "ERROR: DB password secret not found"
  exit 1
fi

# Load connection URL secret (optional)
if [ -n "${VAULT_CONNECTION_URL_FILE:-}" ] && [ -f "$VAULT_CONNECTION_URL_FILE" ]; then
  VAULT_CONNECTION_URL=$(cat "$VAULT_CONNECTION_URL_FILE")
elif [ -f /run/secrets/vault_connection_url ]; then
  VAULT_CONNECTION_URL=$(cat /run/secrets/vault_connection_url)
else
  VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@infra_postgres:5432/vaultdb?sslmode=disable"
fi

export PGPASSWORD="$DB_PASS"
export VAULT_CONNECTION_URL

log "Using Vault DB connection: $VAULT_CONNECTION_URL"

if [ ! -f "$TEMPLATE" ]; then
  log "ERROR: template $TEMPLATE not found"
  exit 1
fi

# Generate config
if command -v envsubst >/dev/null 2>&1; then
  log "Generating $OUT using envsubst"
  envsubst < "$TEMPLATE" > "$OUT" || { log "ERROR: envsubst failed"; exit 1; }
else
  log "envsubst not available; using sed fallback for VAULT_CONNECTION_URL"
  sed "s|@VAULT_CONNECTION_URL@|$VAULT_CONNECTION_URL|g; s|\\\${VAULT_CONNECTION_URL}|$VAULT_CONNECTION_URL|g; s|{{VAULT_CONNECTION_URL}}|$VAULT_CONNECTION_URL|g" "$TEMPLATE" > "$OUT" || { log "ERROR: sed failed"; exit 1; }
fi

OUT_SIZE=$(wc -c < "$OUT" 2>/dev/null || echo unknown)
log "Generated $OUT (size=${OUT_SIZE})"

# Copy optional unseal script
if [ -f /vault/unseal.sh ]; then
  cp /vault/unseal.sh /tmp/unseal.sh || true
  chmod +x /tmp/unseal.sh || true
else
  log "No /vault/unseal.sh found"
fi

# Wait for Postgres with multiple fallbacks
wait_for_pg() {
  HOST=infra_postgres
  PORT=5432
  USER=vault_app
  MAX_WAIT=60
  waited=0

  if command -v pg_isready >/dev/null 2>&1; then
    log "Waiting for Postgres using pg_isready..."
    until PGPASSWORD="$DB_PASS" pg_isready -h "$HOST" -p "$PORT" -U "$USER" >/dev/null 2>&1; do
      sleep 2
      waited=$((waited+2))
      if [ "$waited" -ge "$MAX_WAIT" ]; then return 1; fi
    done
    return 0
  fi

  if command -v nc >/dev/null 2>&1; then
    log "Waiting for Postgres using nc..."
    until nc -z "$HOST" "$PORT" >/dev/null 2>&1; do
      sleep 2
      waited=$((waited+2))
      if [ "$waited" -ge "$MAX_WAIT" ]; then return 1; fi
    done
    return 0
  fi

  log "Using /dev/tcp probe for Postgres..."
  until timeout 1 sh -c "cat < /dev/null > /dev/tcp/$HOST/$PORT" >/dev/null 2>&1; do
    sleep 2
    waited=$((waited+2))
    if [ "$waited" -ge "$MAX_WAIT" ]; then return 1; fi
  done
  return 0
}

log "Waiting for Postgres to be ready..."
if ! wait_for_pg; then
  log "Postgres not ready; exiting."
  exit 1
fi

# Start Vault in background
log "Launching Vault with $OUT"
vault server -config="$OUT" > /vault/logs/vault.stdout 2>&1 &
VAULT_PID=$!

trap "log 'Caught signal, shutting down Vault...'; kill $VAULT_PID 2>/dev/null || true; wait $VAULT_PID 2>/dev/null || true; exit 0" TERM INT

# Function to get HTTP status from Vault health endpoint with fallbacks
vault_health_code() {
  HEALTH_URL="http://127.0.0.1:8200/v1/sys/health"

  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null || echo "000"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    status=$(wget --server-response --spider "$HEALTH_URL" 2>&1 | awk '/HTTP\// {print $2; exit}')
    [ -z "$status" ] && echo "000" || echo "$status"
    return
  fi

  if command -v nc >/dev/null 2>&1; then
    status=$(printf 'GET /v1/sys/health HTTP/1.0\r\nHost: localhost\r\n\r\n' | nc -w 2 127.0.0.1 8200 2>/dev/null | head -n1 | awk '{print $2}')
    [ -z "$status" ] && echo "000" || echo "$status"
    return
  fi

  # /dev/tcp fallback
  if timeout 1 sh -c "cat < /dev/null > /dev/tcp/127.0.0.1/8200" >/dev/null 2>&1; then
    exec 3<>/dev/tcp/127.0.0.1/8200 2>/dev/null || true
    if [ -e /proc/$$/fd/3 ] || true; then
      printf 'GET /v1/sys/health HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3
      status=$(head -n1 <&3 2>/dev/null | awk '{print $2}')
      exec 3>&-
      [ -z "$status" ] && echo "000" || echo "$status"
      return
    fi
  fi

  echo "000"
}

log "Waiting for Vault to become healthy (handles init/unseal)..."
MAX_HEALTH_WAIT=180
health_waited=0
sleep_interval=2

while :; do
  status=$(vault_health_code)
  log "Vault health status: $status"

  case "$status" in
    200)
      log "Vault is initialized, unsealed and active."
      break
      ;;
    429)
      log "Vault is standby (429). If running HA, this node is standby; waiting..."
      ;;
    503)
      log "Vault is sealed (503). Running unseal script if present..."
      if [ -f /tmp/unseal.sh ]; then
        /tmp/unseal.sh || log "Warning: unseal script returned non-zero"
      fi
      ;;
    501)
      log "Vault not initialized (501). Running init/unseal script if present..."
      if [ -f /tmp/unseal.sh ]; then
        /tmp/unseal.sh || log "Warning: init/unseal script returned non-zero"
      fi
      ;;
    000)
      log "Vault health endpoint not reachable yet."
      ;;
    *)
      log "Vault returned unexpected health code: $status"
      ;;
  esac

  sleep "$sleep_interval"
  health_waited=$((health_waited + sleep_interval))
  if [ "$health_waited" -ge "$MAX_HEALTH_WAIT" ]; then
    log "Timed out waiting for Vault health (${MAX_HEALTH_WAIT}s). Exiting."
    kill $VAULT_PID 2>/dev/null || true
    exit 1
  fi
done

log "Vault ready and unsealed. PID=$VAULT_PID"

# Tail logs and wait for Vault exit
tail -F /vault/logs/vault.stdout &

wait $VAULT_PID
