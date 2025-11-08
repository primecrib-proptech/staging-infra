#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting Vault setup..."

DB_PASS=$(cat /run/secrets/db_password)
export PGPASSWORD="$DB_PASS"
VAULT_CONNECTION_URL="postgres://vault_app:${DB_PASS}@infra_postgres:5432/vaultdb?sslmode=disable"
export VAULT_CONNECTION_URL
log "Using Vault DB connection: $VAULT_CONNECTION_URL"

# Try to ensure useful networking/tools are available
install_envsubst() {
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache gettext >/dev/null 2>&1 || return 1
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y gettext-base >/dev/null 2>&1 || return 1
  fi
  return 0
}

# Install postgres client if possible (used for pg_isready)
if command -v apk >/dev/null 2>&1; then
  apk add --no-cache postgresql-client >/dev/null 2>&1 || true
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y postgresql-client >/dev/null 2>&1 || true
fi

# Ensure template exists
TEMPLATE=/vault/config/config.hcl
OUT=/vault/config/config.generated.hcl

if [ ! -f "$TEMPLATE" ]; then
  log "ERROR: template $TEMPLATE not found. Cannot generate $OUT"
  exit 1
fi

# Ensure envsubst is available (try to install if missing)
if ! command -v envsubst >/dev/null 2>&1; then
  log "envsubst not found; attempting to install..."
  if ! install_envsubst; then
    log "ERROR: could not install envsubst. Ensure gettext/envsubst is available in the image."
    exit 1
  fi
  # recheck
  if ! command -v envsubst >/dev/null 2>&1; then
    log "ERROR: envsubst still not available after install attempt."
    exit 1
  fi
fi

# Generate config and verify
log "Generating $OUT from $TEMPLATE"
if ! envsubst < "$TEMPLATE" > "$OUT"; then
  log "ERROR: envsubst failed to generate $OUT"
  exit 1
fi

if [ ! -s "$OUT" ]; then
  log "ERROR: generated file $OUT is empty"
  exit 1
fi

log "Generated $OUT (size=$(stat -c%s "$OUT" 2>/dev/null || echo unknown))"

# copy unseal script if read-only
if [ -f ./vault/unseal.sh ]; then
  cp ./vault/unseal.sh /tmp/unseal.sh
  chmod +x /tmp/unseal.sh
else
  log "Warning: ./vault/unseal.sh not found"
fi

trap "log 'Caught SIGTERM, shutting down Vault...'; kill $VAULT_PID 2>/dev/null || true; exit 0" TERM INT

# (rest of original script continues: wait_for_pg, start vault, unseal, etc.)
# --- preserve existing wait_for_pg and vault start logic below ---
