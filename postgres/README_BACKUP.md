# PostgreSQL backup to MinIO (S3)

`pg_backup.sh` dumps all non-system databases from the Postgres Docker container, optionally encrypts them with GPG, and uploads to MinIO (or any S3-compatible storage).

## Requirements

- `docker` (to run `docker exec` against the Postgres container)
- `gzip`, `gpg` (optional, only if using encryption)
- **AWS CLI** (for S3/MinIO upload):
  - Debian/Ubuntu: `sudo apt-get install -y awscli | sudo snap install aws-cli --classic`
  - Or: `pip install awscli`

## Environment variables

Set these where you run the script (e.g. in a cron file or a small wrapper script that sources `.env`).

| Variable | Required | Description |
|----------|----------|-------------|
| `S3_ENDPOINT_URL` | Yes | MinIO/S3 endpoint, e.g. `http://minio:9000` (from same host as MinIO) or `https://minio.s3.cyberstarsng.com` |
| `S3_BUCKET` | Yes | Bucket name, e.g. `postgres-backups` |
| `AWS_ACCESS_KEY_ID` | Yes | MinIO access key (same as MinIO root user or a dedicated backup user) |
| `AWS_SECRET_ACCESS_KEY` | Yes | MinIO secret key |
| `S3_PREFIX` | No | Prefix (folder) in bucket (default: `postgres`) |
| `BACKUP_ENCRYPTION_PASS` | No | If set, backups are encrypted with GPG before upload |
| `BACKUP_DIR` | No | Local temp directory (default: `/var/backups/postgres`) |
| `LOG_FILE` | No | Log path (default: `/var/log/pg_backup.log`) |
| `POSTGRES_CONTAINER_PATTERN` | No | Docker filter name (default: `postgres`) |
| `KEEP_LOCAL_AFTER_UPLOAD` | No | Set to `true` to keep local files after upload (default: delete) |

## MinIO setup

1. Create a bucket (e.g. `postgres-backups`) in MinIO (Console or `mc mb`).
2. Use MinIO root credentials or create an access key for a dedicated backup user and set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
3. (Optional) Configure lifecycle rules on the bucket to expire or tier old backups.

## Automation (cron)

Example: run daily at 2:00 AM. Use a wrapper that sets env vars:

```bash
# /etc/cron.d/pg-backup
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

# Load env from file (create with restricted permissions, e.g. 600)
0 2 * * * root . /etc/postgres-backup.env && /opt/scripts/postgres/pg_backup.sh
```

Example `/etc/postgres-backup.env`:

```bash
export S3_ENDPOINT_URL="http://minio:9000"
export S3_BUCKET="postgres-backups"
export AWS_ACCESS_KEY_ID="your-minio-access-key"
export AWS_SECRET_ACCESS_KEY="your-minio-secret-key"
# optional:
# export BACKUP_ENCRYPTION_PASS="your-gpg-passphrase"
# export S3_PREFIX="postgres/staging"
```

If the script runs on the same host as Docker and MinIO is in the same Docker network, use `http://minio:9000`. If it runs elsewhere, use the public MinIO URL (e.g. `https://minio.s3.cyberstarsng.com`).

## Restore

- Download the object from MinIO (e.g. with `aws s3 cp --endpoint-url ...` or MinIO Console).
- If encrypted: `gpg -d backup.sql.gz.gpg | gunzip | docker exec -i <postgres_container> psql -U postgres -d your_db`.
