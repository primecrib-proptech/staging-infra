#!/bin/bash

# PostgreSQL backup: dump -> (optional) encrypt -> upload to MinIO/S3.
# Supports two modes:
#   1. Container mode: run inside a container with secrets mounted at /run/secrets/
#      (PGHOST, MinIO and encryption read from secrets; no docker exec)
#   2. Host mode: run on host with env vars set; finds Postgres via docker and uses docker exec

set -e
set -o pipefail

# --- Configuration (override via environment; container mode fills from /run/secrets) ---
CONTAINER_NAME_PATTERN="${POSTGRES_CONTAINER_PATTERN:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgres}"
DATE=$(date +%Y-%m-%d_%H-%M)
LOG_FILE="${LOG_FILE:-/var/log/pg_backup.log}"
KEEP_LOCAL_AFTER_UPLOAD="${KEEP_LOCAL_AFTER_UPLOAD:-false}"

# Container mode: when secrets exist, read MinIO and optional encryption from them
if [ -r /run/secrets/minio_root_password ]; then
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-minioadmin}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(cat /run/secrets/minio_root_password)}"
    export S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-http://minio:9000}"
    export S3_BUCKET="${S3_BUCKET:-postgres-backups}"
    export S3_PREFIX="${S3_PREFIX:-postgres}"
    [ -r /run/secrets/postgres_backup_encryption_pass ] && export BACKUP_ENCRYPTION_PASS="${BACKUP_ENCRYPTION_PASS:-$(cat /run/secrets/postgres_backup_encryption_pass)}"
    # Postgres connection for container mode (same network as postgres service)
    if [ -r /run/secrets/db_user ] && [ -r /run/secrets/postgres_password ]; then
        export PGHOST="${PGHOST:-postgres}"
        export PGPORT="${PGPORT:-5432}"
        export PGUSER="${PGUSER:-$(cat /run/secrets/db_user)}"
        export PGPASSWORD="${PGPASSWORD:-$(cat /run/secrets/postgres_password)}"
    fi
fi

ENCRYPTION_PASS="${BACKUP_ENCRYPTION_PASS:-}"
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-postgres}"

# --- Helpers ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

ensure_aws_cli() {
    command -v aws &> /dev/null || { log "aws CLI not found."; return 1; }
}

# --- Validation ---
log "Starting PostgreSQL backup..."

if [ -z "$S3_ENDPOINT_URL" ] || [ -z "$S3_BUCKET" ]; then
    log "Error: S3_ENDPOINT_URL and S3_BUCKET must be set (or run inside backup container with secrets mounted)."
    exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    log "Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set for MinIO/S3."
    exit 1
fi

if ! ensure_aws_cli; then
    exit 1
fi

if ! mkdir -p "$BACKUP_DIR"; then
    log "Error: Failed to create backup directory $BACKUP_DIR"
    exit 1
fi

# --- Obtain database list: container mode (PGHOST) vs host mode (docker exec) ---
CONTAINER_MODE=
if [ -n "$PGHOST" ] && [ -n "$PGUSER" ] && [ -n "$PGPASSWORD" ]; then
    CONTAINER_MODE=1
    log "Using container mode (PGHOST=${PGHOST})..."
fi

if [ -n "$CONTAINER_MODE" ]; then
    export PGPASSWORD
    log "Fetching database list..."
    if ! DATABASES=$(psql -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" -d postgres -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"); then
        log "Error: Failed to list databases. Is Postgres reachable at ${PGHOST}?"
        exit 1
    fi
else
    log "Finding Postgres container (pattern: ${CONTAINER_NAME_PATTERN})..."
    CONTAINER_ID=$(docker ps --format "{{.ID}}" --filter "name=${CONTAINER_NAME_PATTERN}" | head -n 1)
    if [ -z "$CONTAINER_ID" ]; then
        log "Error: No running container found matching '${CONTAINER_NAME_PATTERN}'"
        exit 1
    fi
    log "Found container: $CONTAINER_ID"
    log "Fetching database list..."
    if ! DATABASES=$(docker exec -u postgres "$CONTAINER_ID" psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"); then
        log "Error: Failed to list databases. Is the container healthy?"
        exit 1
    fi
fi

if [ -z "$DATABASES" ]; then
    log "No user databases found. Exiting."
    exit 0
fi

# --- Backup each database ---
for DB_NAME in $DATABASES; do
    log "Processing database: $DB_NAME"

    FILE="$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"
    UPLOAD_FILE="$FILE"
    ENCRYPTED_FILE="${FILE}.gpg"

    # 1. Dump and compress
    log "Dumping $DB_NAME..."
    if [ -n "$CONTAINER_MODE" ]; then
        if ! pg_dump -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" "$DB_NAME" | gzip > "$FILE"; then
            log "Error: Failed to dump $DB_NAME"
            [ -f "$FILE" ] && rm -f "$FILE"
            continue
        fi
    else
        if ! docker exec -u postgres "$CONTAINER_ID" pg_dump "$DB_NAME" | gzip > "$FILE"; then
            log "Error: Failed to dump $DB_NAME"
            [ -f "$FILE" ] && rm -f "$FILE"
            continue
        fi
    fi

    # 2. Optional encryption
    if [ -n "$ENCRYPTION_PASS" ]; then
        log "Encrypting backup..."
        if ! gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$ENCRYPTION_PASS" --pinentry-mode loopback -o "$ENCRYPTED_FILE" "$FILE"; then
            log "Error: Encryption failed for $DB_NAME"
            rm -f "$FILE"
            continue
        fi
        rm -f "$FILE"
        UPLOAD_FILE="$ENCRYPTED_FILE"
    fi

    # 3. Upload to MinIO/S3
    S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}/${DB_NAME}_${DATE}.sql.gz"
    [ -n "$ENCRYPTION_PASS" ] && S3_URI="${S3_URI}.gpg"

    log "Uploading to ${S3_ENDPOINT_URL} -> ${S3_URI}..."
    if AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
       AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
       aws s3 cp "$UPLOAD_FILE" "$S3_URI" --endpoint-url "$S3_ENDPOINT_URL" --only-show-errors; then
        log "Upload successful: $S3_URI"
        if [ "$KEEP_LOCAL_AFTER_UPLOAD" != "true" ]; then
            rm -f "$UPLOAD_FILE"
        fi
    else
        log "Error: Upload failed for $DB_NAME"
    fi
done

log "Backup process completed."
