#!/bin/bash

# Config
DB_USER="postgres"
DB_PASS="${POSTGRES_PASS}"
# Set a strong encryption password in your environment or hardcode here (not recommended)
ENCRYPTION_PASS="${BACKUP_ENCRYPTION_PASS}"
BACKUP_DIR="/var/backups/postgres"
GDRIVE_FOLDER_ID="${GOOGLE_DRIVE_FOLDER_ID}"   # create a folder in drive and copy ID
DATE=$(date +%Y-%m-%d_%H-%M)

# Check for encryption password
if [ -z "$ENCRYPTION_PASS" ]; then
  echo "Error: BACKUP_ENCRYPTION_PASS is not set."
  exit 1
fi

# Ensure folder exists
mkdir -p $BACKUP_DIR

# Get list of databases (excluding templates and postgres system db if desired)
# You can filter specific DBs here if needed
DATABASES=$(PGPASSWORD=$DB_PASS psql -U $DB_USER -h localhost -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

for DB_NAME in $DATABASES; do
    echo "Backing up database: $DB_NAME"
    
    FILE="$BACKUP_DIR/${DB_NAME}_$DATE.sql.gz"
    ENCRYPTED_FILE="${FILE}.gpg"

    # Dump and compress
    PGPASSWORD=$DB_PASS pg_dump -U $DB_USER -h localhost $DB_NAME | gzip > $FILE

    # Encrypt (Safe and Secure) using GPG with AES-256
    gpg --symmetric --cipher-algo AES256 --batch --passphrase "$ENCRYPTION_PASS" -o "$ENCRYPTED_FILE" "$FILE"

    if [ -f "$ENCRYPTED_FILE" ]; then
        # Upload encrypted file to Google Drive
        /usr/local/bin/gdrive upload --parent $GDRIVE_FOLDER_ID "$ENCRYPTED_FILE"
        
        # Remove local files after upload to save space
        rm "$FILE" "$ENCRYPTED_FILE"
    else
        echo "Encryption failed for $DB_NAME"
    fi
done

# Delete old backups from Google Drive (Optional - requires gdrive list/delete logic)
# Keeping local cleanup if you decide to keep local copies:
# find $BACKUP_DIR -type f -mtime +7 -name "*.gpg" -delete

# sudo chmod +x /usr/local/bin/pg_backup.sh
# crontab -e
# 0 2 * * * export POSTGRES_PASS=yourpass; export BACKUP_ENCRYPTION_PASS=securepass; /usr/local/bin/pg_backup.sh >> /var/log/pg_backup.log 2>&1