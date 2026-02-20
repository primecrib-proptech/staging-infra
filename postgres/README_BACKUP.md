# PostgreSQL backup to MinIO (S3)

`pg_backup.sh` dumps all non-system databases, optionally encrypts them with GPG, and uploads to MinIO (or any S3-compatible storage).

## Recommended: run inside the backup container (secrets on container, not host)

The stack includes a **postgres-backup** service that runs the script inside a container. Credentials are read from Docker secrets (`/run/secrets/`), so nothing is stored in env files on the host.

### Setup

1. **Create the MinIO bucket**  
   In MinIO (Console or `mc`), create a bucket named `postgres-backups` (or set `S3_BUCKET` in the service env).

2. **Build the backup image** (required once; stack deploy does not build):
   ```bash
   docker build -t postgres-backup:latest -f postgres/Dockerfile.backup postgres/
   ```

3. **Deploy the stack** (includes `postgres-backup`):
   ```bash
   docker stack deploy -c docker-stack.yml <stack-name>
   ```

The backup container uses these **secrets** (already in your stack): `db_name`, `db_user`, `postgres_password`, `minio_root_password`, `postgres_backup_encryption_pass`. It connects to Postgres over the `backend` network (`PGHOST=postgres`) and uploads to MinIO at `http://minio:9000`.

### Schedule

Cron inside the container runs the backup **daily at 02:00 UTC**. No host cron or env file needed.

### Run a backup manually

```bash
docker exec $(docker ps -q -f name=postgres-backup) /usr/local/bin/pg_backup.sh
```

---

## Alternative: run on the host

If you run the script on the host (e.g. host cron), you must set **environment variables** (no secrets available on the host).

### Requirements

- `docker` (for finding the Postgres container and `docker exec`)
- `gzip`, `gpg` (optional, for encryption)
- **AWS CLI**: `apt-get install -y awscli` or `pip install awscli`

### Environment variables (host mode)

| Variable | Required | Description |
|----------|----------|-------------|
| `S3_ENDPOINT_URL` | Yes | e.g. `http://minio:9000` or `https://minio.s3.cyberstarsng.com` |
| `S3_BUCKET` | Yes | e.g. `postgres-backups` |
| `AWS_ACCESS_KEY_ID` | Yes | MinIO access key |
| `AWS_SECRET_ACCESS_KEY` | Yes | MinIO secret key |
| `S3_PREFIX` | No | Prefix in bucket (default: `postgres`) |
| `BACKUP_ENCRYPTION_PASS` | No | GPG passphrase; omit to skip encryption |
| `BACKUP_DIR` | No | Local temp dir (default: `/var/backups/postgres`) |
| `LOG_FILE` | No | Log path (default: `/var/log/pg_backup.log`) |
| `POSTGRES_CONTAINER_PATTERN` | No | Docker filter (default: `postgres`) |
| `KEEP_LOCAL_AFTER_UPLOAD` | No | Set to `true` to keep local files |

Example env file for host cron:

```bash
# /etc/postgres-backup.env (chmod 600)
export S3_ENDPOINT_URL="http://minio:9000"
export S3_BUCKET="postgres-backups"
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="your-minio-password"
# export BACKUP_ENCRYPTION_PASS="your-gpg-passphrase"
```

Cron:

```bash
0 2 * * * root . /etc/postgres-backup.env && /path/to/postgres/pg_backup.sh
```

---

## Restore

- Download the object from MinIO (Console or `aws s3 cp --endpoint-url ...`).
- If encrypted:  
  `gpg -d backup.sql.gz.gpg | gunzip | docker exec -i <postgres_container> psql -U <user> -d your_db`
