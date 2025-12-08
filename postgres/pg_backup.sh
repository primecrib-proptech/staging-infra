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
GDRIVE_CMD="/usr/local/bin/gdrive"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- INSTALLATION CHECK ---
install_gdrive() {
    log "gdrive not found. Attempting to install..."
    # Download the latest Linux x64 release from glotlabs/gdrive
    if wget -O "$GDRIVE_CMD" https://github.com/glotlabs/gdrive/releases/download/3.0.0/gdrive-linux-x64; then
        chmod +x "$GDRIVE_CMD"
        log "gdrive installed successfully to $GDRIVE_CMD"
    else
        log "Error: Failed to download gdrive."
        return 1
    fi
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

# Check/Install gdrive
if ! command -v "$GDRIVE_CMD" &> /dev/null; then
    if ! install_gdrive; then
        exit 1
    fi
fi

# Check for gdrive authentication (simple check if 'gdrive account list' returns anything)
# Note: On first run, you MUST run 'gdrive account add' manually in the terminal!
if ! "$GDRIVE_CMD" account list &> /dev/null; then
    log "Error: gdrive is not authenticated. Please run '$GDRIVE_CMD account add' manually on the server to link your Google account."
    # We exit here because we can't backup to cloud without auth
    exit 1
fi

# Find the Docker container ID
log "Finding Postgres container..."
CONTAINER_ID=$(docker ps --format "{{.ID}}" --filter "name=${CONTAINER_NAME_PATTERN}" | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    log "Error: No running container found matching pattern '${CONTAINER_NAME_PATTERN}'"
    exit 1
fi
log "Found container ID: $CONTAINER_ID"

# 1. Fetch Databases
log "Fetching database list from container..."
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
    if ! docker exec -u postgres "$CONTAINER_ID" pg_dump "$DB_NAME" | gzip > "$FILE"; then
        log "Error: Failed to dump database $DB_NAME"
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
        if "$GDRIVE_CMD" upload --parent "$GDRIVE_FOLDER_ID" "$ENCRYPTED_FILE"; then
            log "Upload successful."
            rm "$FILE" "$ENCRYPTED_FILE"
        else
            log "Error: Google Drive upload failed."
        fi
    fi
done

log "Backup process completed."