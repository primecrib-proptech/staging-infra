#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting Vault setup..."

DB_PASS=$(cat /run/secrets/db_password)
export PGPASSWORD="$DB_PASS"
VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@infra_postgres:5432/vaultdb?sslmode=disable"
export VAULT_CONNECTION_URL
log "Using Vault DB connection: $VAULT_CONNECTION_URL"

# Try to ensure useful networking tools are available
if command -v apk >/dev/null 2>&1; then
  apk add --no-cache gettext postgresql-client >/dev/null 2>&1 || true
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y gettext postgresql-client >/dev/null 2>&1 || true
fi

envsubst < /vault/config/config.hcl > /vault/config/config.generated.hcl

# Optional: copy unseal script if read-only
cp ./vault/unseal.sh /tmp/unseal.sh
chmod +x /tmp/unseal.sh

trap "log 'Caught SIGTERM, shutting down Vault...'; kill $VAULT_PID 2>/dev/null || true; exit 0" TERM INT

log "Waiting for Postgres to be ready..."
MAX_WAIT=60
WAITED=0

wait_for_pg() {
  HOST=infra_postgres
  PORT=5432
  USER=vault_app

  if command -v pg_isready >/dev/null 2>&1; then
    # Use PGPASSWORD in environment so authentication checks succeed
    until PGPASSWORD="$DB_PASS" pg_isready -h "$HOST" -p "$PORT" -U "$USER" >/dev/null 2>&1; do
      sleep 2
      WAITED=$((WAITED + 2))
      if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        return 1
      fi
    done
    return 0
  fi

  # Fallback: TCP probe using nc (busybox/netcat)
  if command -v nc >/dev/null 2>&1; then
    until nc -z "$HOST" "$PORT" >/dev/null 2>&1; do
      sleep 2
      WAITED=$((WAITED + 2))
      if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        return 1
      fi
    done
    return 0
  fi

  # Last fallback: try a simple curl to the postgres port (will fail on some images)
  until timeout 1 sh -c "cat < /dev/null > /dev/tcp/$HOST/$PORT"  >/dev/null 2>&1; do
    sleep 2
    WAITED=$((WAITED + 2))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
      return 1
    fi
  done

  return 0
}

if ! wait_for_pg; then
  log "Postgres not ready after $MAX_WAIT seconds, exiting."
  exit 1
fi

log "Launching Vault..."
vault server -config=/vault/config.generated.hcl &
VAULT_PID=$!

log "Waiting for Vault to be ready..."
until curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1; do
    sleep 1
done

log "Running unseal script..."
/tmp/unseal.sh

log "Vault ready and unsealed. PID=$VAULT_PID"

wait $VAULT_PID