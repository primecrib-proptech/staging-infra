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

MAX_UNSEAL_ATTEMPTS=${MAX_UNSEAL_ATTEMPTS:-5}
UNSEAL_ATTEMPTS=0
UNSEAL_ATTEMPTED=0
VAULT_UNSEAL_KEY_FILE=${VAULT_UNSEAL_KEY_FILE:-/run/secrets/vault_unseal_key}
UNSEAL_BACKOFF_BASE=2

attempt_unseal() {
  # Prevent concurrent/duplicate attempts in the same run
  if [ "$UNSEAL_ATTEMPTED" = "1" ]; then
    log "Unseal already attempted; skipping additional unseal attempts."
    return 1
  fi
  UNSEAL_ATTEMPTED=1

  # Prefer executing a provided unseal/init script once
  if [ -x /tmp/unseal.sh ]; then
    log "Running /tmp/unseal.sh once..."
    if /tmp/unseal.sh >/dev/null 2>&1; then
      log "/tmp/unseal.sh succeeded."
      return 0
    else
      log "/tmp/unseal.sh failed."
      # fall through to attempt operator unseal if key exists
    fi
  fi

  # Require vault CLI and a key file to use operator unseal
  if ! command -v vault >/dev/null 2>&1; then
    log "vault CLI not found; cannot perform operator unseal."
    return 1
  fi

  if [ ! -f "$VAULT_UNSEAL_KEY_FILE" ]; then
    log "No unseal key file at $VAULT_UNSEAL_KEY_FILE; cannot unseal."
    return 1
  fi

  KEY_CONTENT=$(cat "$VAULT_UNSEAL_KEY_FILE" 2>/dev/null || true)
  if [ -z "$KEY_CONTENT" ]; then
    log "Unseal key file is empty."
    return 1
  fi

  # Try operator unseal with limited retries and exponential backoff
  while [ "$UNSEAL_ATTEMPTS" -lt "$MAX_UNSEAL_ATTEMPTS" ]; do
    UNSEAL_ATTEMPTS=$((UNSEAL_ATTEMPTS + 1))
    log "Attempting vault operator unseal (attempt ${UNSEAL_ATTEMPTS}/${MAX_UNSEAL_ATTEMPTS})..."
    if vault operator unseal "$KEY_CONTENT" >/dev/null 2>&1; then
      log "vault operator unseal succeeded."
      return 0
    fi
    sleep_time=$((UNSEAL_BACKOFF_BASE ** UNSEAL_ATTEMPTS))
    log "unseal attempt failed; backing off ${sleep_time}s before retry."
    sleep "$sleep_time"
  done

  log "Exceeded unseal attempts (${MAX_UNSEAL_ATTEMPTS}); will not retry in this run."
  return 1
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
      log "Vault is sealed (503). Attempting a guarded unseal..."
         attempt_unseal || log "Guarded unseal did not succeed; waiting before next health check."
      ;;
    501)
      log "Vault not initialized (501). Attempting init/unseal if script or key available..."
        # If init is required you may want to run an init script once; attempt_unseal checks /tmp/unseal.sh
        attempt_unseal || log "Init/unseal attempt did not succeed; waiting before next health check."
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
