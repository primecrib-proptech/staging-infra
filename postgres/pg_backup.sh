#!/bin/bash

# Enable strict error handling
set -e
set -o pipefail

# Config
# Ensure these match your actual database credentials
DB_USER="${DB_USER:-postgres}"
DB_PASS="${POSTGRES_PASS}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# Encryption
ENCRYPTION_PASS="${BACKUP_ENCRYPTION_PASS}" 

BACKUP_DIR="/var/backups/postgres"
GDRIVE_FOLDER_ID="YOUR_GOOGLE_DRIVE_FOLDER_ID"
DATE=$(date +%Y-%m-%d_%H-%M)
LOG_FILE="/var/log/pg_backup.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup process..."

# Check for encryption password
if [ -z "$ENCRYPTION_PASS" ]; then
  log "Error: BACKUP_ENCRYPTION_PASS is not set."
  exit 1
fi

# Ensure backup directory exists
if ! mkdir -p "$BACKUP_DIR"; then
    log "Error: Failed to create backup directory $BACKUP_DIR"
    exit 1
fi

# Check dependencies
for cmd in pg_dump gpg gzip; do
    if ! command -v $cmd &> /dev/null; then
        log "Error: $cmd could not be found."
        exit 1
    fi
done

# 1. Fetch Databases
log "Fetching database list from $DB_HOST..."
# Added -w to prevent interactive password prompt hanging the script
if ! DATABASES=$(PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -w -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"); then
    log "Error: Failed to connect to database. Check credentials, host, and port. Ensure DB_USER and POSTGRES_PASS are correct."
    exit 1
fi

for DB_NAME in $DATABASES; do
    log "Processing database: $DB_NAME"
    
    FILE="$BACKUP_DIR/${DB_NAME}_$DATE.sql.gz"
    ENCRYPTED_FILE="${FILE}.gpg"

    # 2. Dump and Compress
    log "Dumping $DB_NAME..."
    # Added -w to prevent hang
    if ! PGPASSWORD="$DB_PASS" pg_dump -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -w "$DB_NAME" | gzip > "$FILE"; then
        log "Error: Failed to dump database $DB_NAME"
        # Clean up empty file if created
        [ -f "$FILE" ] && rm "$FILE"
        continue
    fi

    # 3. Encrypt
    log "Encrypting backup..."
    # --pinentry-mode loopback is often needed for batch mode on modern GPG
    if ! gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$ENCRYPTION_PASS" --pinentry-mode loopback -o "$ENCRYPTED_FILE" "$FILE"; then
         log "Error: Encryption failed for $DB_NAME"
         rm "$FILE"
         continue
    fi

    # 4. Upload
    if [ -f "$ENCRYPTED_FILE" ]; then
        log "Uploading to Google Drive..."
        # Check if gdrive command exists
        if command -v /usr/local/bin/gdrive &> /dev/null; then
             if /usr/local/bin/gdrive upload --parent "$GDRIVE_FOLDER_ID" "$ENCRYPTED_FILE"; then
                log "Upload successful."
                # Remove local files after upload
                rm "$FILE" "$ENCRYPTED_FILE"
             else
                log "Error: Google Drive upload failed."
             fi
        else
            log "Warning: gdrive command not found at /usr/local/bin/gdrive. Skipping upload."
        fi
    fi
done

log "Backup process completed."