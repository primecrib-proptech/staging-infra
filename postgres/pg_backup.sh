#!/bin/bash

# PostgreSQL backup script: dump from Docker container -> (optional) encrypt -> upload to MinIO/S3.
# Run via cron for automation, e.g. daily: 0 2 * * * /path/to/pg_backup.sh

set -e
set -o pipefail

# --- Configuration (override via environment) ---
CONTAINER_NAME_PATTERN="${POSTGRES_CONTAINER_PATTERN:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgres}"
DATE=$(date +%Y-%m-%d_%H-%M)
LOG_FILE="${LOG_FILE:-/var/log/pg_backup.log}"
S3_ENDPOINT_URL=http://minio:9000
S3_BUCKET=postgres-backups
S3_PREFIX=postgres
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=$(cat /run/secrets/minio_root_password)
BACKUP_ENCRYPTION_PASS=$(cat /run/secrets/postgres_backup_encryption_pass)

# Optional: encrypt backups with GPG (leave unset to skip encryption)
ENCRYPTION_PASS="${BACKUP_ENCRYPTION_PASS:-}"

# MinIO / S3 (required for upload)
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-}"   # e.g. http://minio:9000 or https://minio.s3.cyberstarsng.com
S3_BUCKET="${S3_BUCKET:-}"               # e.g. postgres-backups
S3_PREFIX="${S3_PREFIX:-postgres}"       # optional prefix (folder) in bucket, e.g. postgres/production
# Use standard AWS env vars for MinIO credentials:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   (or MINIO_ACCESS_KEY / MINIO_SECRET_KEY mapped to these if you prefer)

# Retention: delete local files after upload; optional S3 retention is via MinIO lifecycle
KEEP_LOCAL_AFTER_UPLOAD="${KEEP_LOCAL_AFTER_UPLOAD:-false}"

# --- Helpers ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Ensure AWS CLI is available (used for S3-compatible MinIO)
ensure_aws_cli() {
    if command -v aws &> /dev/null; then
        return 0
    fi
    log "aws CLI not found. Install with: apt-get install -y awscli  # or: pip install awscli"
    return 1
}

# --- Validation ---
log "Starting PostgreSQL backup (Docker -> MinIO/S3)..."

if [ -z "$S3_ENDPOINT_URL" ] || [ -z "$S3_BUCKET" ]; then
    log "Error: S3_ENDPOINT_URL and S3_BUCKET must be set (e.g. in .env or cron)."
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

# --- Find Postgres container ---
log "Finding Postgres container (pattern: ${CONTAINER_NAME_PATTERN})..."
CONTAINER_ID=$(docker ps --format "{{.ID}}" --filter "name=${CONTAINER_NAME_PATTERN}" | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    log "Error: No running container found matching '${CONTAINER_NAME_PATTERN}'"
    exit 1
fi
log "Found container: $CONTAINER_ID"

# --- List databases (exclude template and default postgres) ---
log "Fetching database list..."
if ! DATABASES=$(docker exec -u postgres "$CONTAINER_ID" psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"); then
    log "Error: Failed to list databases. Is the container healthy?"
    exit 1
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
    if ! docker exec -u postgres "$CONTAINER_ID" pg_dump "$DB_NAME" | gzip > "$FILE"; then
        log "Error: Failed to dump $DB_NAME"
        [ -f "$FILE" ] && rm -f "$FILE"
        continue
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
