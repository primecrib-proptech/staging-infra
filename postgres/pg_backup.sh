#!/bin/bash

# Enable strict error handling
set -e
set -o pipefail

# Config
# Pattern to find the container. 'postgres' is usually sufficient if it's unique enough.
CONTAINER_NAME_PATTERN="postgres"

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

# Find the Docker container ID
log "Finding Postgres container..."
# Using docker ps to find the container ID. 
# We filter by name and take the first one found.
CONTAINER_ID=$(docker ps --format "{{.ID}}" --filter "name=${CONTAINER_NAME_PATTERN}" | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    log "Error: No running container found matching pattern '${CONTAINER_NAME_PATTERN}'"
    exit 1
fi
log "Found container ID: $CONTAINER_ID"

# 1. Fetch Databases
log "Fetching database list from container..."
# We execute 'psql' inside the container as the 'postgres' user.
# This bypasses the need for a password (peer authentication).
if ! DATABASES=$(docker exec -u postgres "$CONTAINER_ID" psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"); then
    log "Error: Failed to list databases from container. Ensure the container is healthy."
    exit 1
fi

for DB_NAME in $DATABASES; do
    log "Processing database: $DB_NAME"
    
    FILE="$BACKUP_DIR/${DB_NAME}_$DATE.sql.gz"
    ENCRYPTED_FILE="${FILE}.gpg"

    # 2. Dump and Compress
    log "Dumping $DB_NAME..."
    # We run pg_dump inside the container and stream the output to gzip on the host
    if ! docker exec -u postgres "$CONTAINER_ID" pg_dump "$DB_NAME" | gzip > "$FILE"; then
        log "Error: Failed to dump database $DB_NAME"
        # Clean up empty file if created
        [ -f "$FILE" ] && rm "$FILE"
        continue
    fi

    # 3. Encrypt
    log "Encrypting backup..."
    if ! gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$ENCRYPTION_PASS" --pinentry-mode loopback -o "$ENCRYPTED_FILE" "$FILE"; then
         log "Error: Encryption failed for $DB_NAME"
         rm "$FILE"
         continue
    fi

    # 4. Upload
    if [ -f "$ENCRYPTED_FILE" ]; then
        log "Uploading to Google Drive..."
        # Check if gdrive command exists (adjust path if your gdrive binary is elsewhere)
        GDRIVE_CMD="/usr/local/bin/gdrive"
        if command -v $GDRIVE_CMD &> /dev/null; then
             if $GDRIVE_CMD upload --parent "$GDRIVE_FOLDER_ID" "$ENCRYPTED_FILE"; then
                log "Upload successful."
                # Remove local files after upload to save space
                rm "$FILE" "$ENCRYPTED_FILE"
             else
                log "Error: Google Drive upload failed."
             fi
        else
            log "Warning: gdrive command not found at $GDRIVE_CMD. Skipping upload."
        fi
    fi
done

log "Backup process completed."