#!/bin/bash
# Production Secrets & Configs Initialization Script
# Usage: ./init-production-secrets.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Create secrets directory for safe storage
SECRETS_DIR="$(pwd)/.secrets"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
log_info "Created secrets directory: $SECRETS_DIR"

# Function to create secret and save to file
create_secret() {
    local secret_name=$1
    local secret_value=$2
    local secret_file="$SECRETS_DIR/$secret_name.txt"

    echo -n "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"

    # Check if secret already exists in Docker
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        log_warn "Secret '$secret_name' already exists in Docker, skipping"
    else
        docker secret create "$secret_name" - < "$secret_file"
        log_info "Created Docker secret: $secret_name"
    fi
}

# Generate random passwords
DB_PASSWORD=$(openssl rand -base64 32)
DB_APP_PASSWORD=$(openssl rand -base64 32)
DB_RO_PASSWORD=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
RABBIT_PASSWORD=$(openssl rand -base64 32)
RABBIT_ERLANG_COOKIE=$(openssl rand -base64 32)
MINIO_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PASSWORD=$(openssl rand -base64 32)
VAULT_ROOT_TOKEN=$(openssl rand -base64 32)
VAULT_UNSEAL_KEY=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
BACKUP_ENCRYPTION=$(openssl rand -base64 32)
IMGPROXY_KEY=$(openssl rand -base64 32)
IMGPROXY_SALT=$(openssl rand -base64 32)

log_info "Generating random secrets..."

# ────────────────────────────────────────
# DATABASE SECRETS
# ────────────────────────────────────────

log_info "Creating database secrets..."
create_secret "db_name" "proptech"
create_secret "db_user" "proptech"
create_secret "db_password" "$DB_PASSWORD"
create_secret "postgres_password" "$POSTGRES_PASSWORD"
create_secret "db_app_password" "$DB_APP_PASSWORD"
create_secret "db_ro_password" "$DB_RO_PASSWORD"

# ────────────────────────────────────────
# VAULT SECRETS
# ────────────────────────────────────────

log_info "Creating Vault secrets..."
create_secret "vault_root_token" "$VAULT_ROOT_TOKEN"
create_secret "vault_unseal_key" "$VAULT_UNSEAL_KEY"
create_secret "vault_connection_url" "https://vault:8200"

# ────────────────────────────────────────
# REDIS SECRETS
# ────────────────────────────────────────

log_info "Creating Redis secrets..."
create_secret "redis_root_password" "$REDIS_PASSWORD"

# ────────────────────────────────────────
# RABBITMQ SECRETS
# ────────────────────────────────────────

log_info "Creating RabbitMQ secrets..."
create_secret "rabbit_password" "$RABBIT_PASSWORD"
create_secret "rabbit_erlang_cookie" "$RABBIT_ERLANG_COOKIE"

# ────────────────────────────────────────
# MINIO SECRETS
# ────────────────────────────────────────

log_info "Creating MinIO secrets..."
create_secret "minio_root_password" "$MINIO_PASSWORD"
create_secret "minio_access_key" "minioadmin"

# ────────────────────────────────────────
# GRAFANA SECRETS
# ────────────────────────────────────────

log_info "Creating Grafana secrets..."
create_secret "grafana_root_password" "$GRAFANA_PASSWORD"

# ────────────────────────────────────────
# TRAEFIK SECRETS (Basic Auth)
# ────────────────────────────────────────

log_info "Creating Traefik secrets..."
TRAEFIK_AUTH=$(echo -n "admin:admin" | tr -d '\n' | docker run --rm -v /dev/stdin:/data -w / alpine sh -c 'apk add --no-cache apache2-utils > /dev/null 2>&1 && htpasswd -nbm admin admin' 2>/dev/null || echo "admin:\$apr1\$PLACEHOLDER\$PLACEHOLDER")
create_secret "traefik_basicauth" "$TRAEFIK_AUTH"

# ────────────────────────────────────────
# APPLICATION SECRETS
# ────────────────────────────────────────

log_info "Creating application secrets..."
create_secret "jwt_secret_key" "$JWT_SECRET"
create_secret "postgres_backup_encryption_pass" "$BACKUP_ENCRYPTION"

# ────────────────────────────────────────
# IMGPROXY SECRETS
# ────────────────────────────────────────

log_info "Creating ImgProxy secrets..."
create_secret "imgproxy_key" "$IMGPROXY_KEY"
create_secret "imgproxy_salt" "$IMGPROXY_SALT"

# ────────────────────────────────────────
# TEMPO S3 CREDENTIALS
# ────────────────────────────────────────

log_info "Creating Tempo S3 credentials..."
TEMPO_CREDS="[default]
aws_access_key_id = minioadmin
aws_secret_access_key = $MINIO_PASSWORD"
create_secret "tempo_s3_credentials" "$TEMPO_CREDS"

# ────────────────────────────────────────
# DOCKER CONFIGS (if needed)
# ────────────────────────────────────────

log_info "Creating Docker configs..."

# IImgProxy watermark (if file exists)
if [ -f "./imgproxy/watermark/logo-96x96.png" ]; then
    if docker config inspect imgproxy_watermark >/dev/null 2>&1; then
        log_warn "Config 'imgproxy_watermark' already exists, skipping"
    else
        docker config create imgproxy_watermark ./imgproxy/watermark/logo-96x96.png
        log_info "Created Docker config: imgproxy_watermark"
    fi
else
    log_warn "ImgProxy watermark file not found at ./imgproxy/watermark/logo-96x96.png"
fi

# ────────────────────────────────────────
# CREATE NETWORKS
# ────────────────────────────────────────

log_info "Creating overlay networks..."

create_network() {
    local net_name=$1
    local encrypted=$2

    if docker network inspect "$net_name" >/dev/null 2>&1; then
        log_warn "Network '$net_name' already exists, skipping"
    else
        if [ "$encrypted" = "true" ]; then
            docker network create --driver overlay --opt encrypted=true "$net_name"
        else
            docker network create --driver overlay "$net_name"
        fi
        log_info "Created network: $net_name"
    fi
}

create_network "traefik-public" "false"
create_network "shared-network" "false"
create_network "observability" "true"

# ────────────────────────────────────────
# SAVE SECRETS REFERENCE
# ────────────────────────────────────────

log_info "Creating secrets reference file..."

SECRETS_REFERENCE="$SECRETS_DIR/SECRETS_REFERENCE.txt"
cat > "$SECRETS_REFERENCE" << EOF
# Production Infrastructure - Secrets Reference
# Generated: $(date)
# KEEP THIS FILE SECURE - Contains sensitive information

## IMPORTANT SECURITY NOTES
1. All secrets are stored in Docker Secrets Manager
2. Local copies in $SECRETS_DIR are for reference only
3. After verification, delete $SECRETS_DIR:
   rm -rf $SECRETS_DIR

4. For recovery/audit, export from Docker manager node:
   docker secret ls
   docker secret inspect SECRET_NAME

## DATABASE
db_name: proptech
db_user: proptech
db_password: $DB_PASSWORD
postgres_password: $POSTGRES_PASSWORD
db_app_password: $DB_APP_PASSWORD
db_ro_password: $DB_RO_PASSWORD

## VAULT
vault_root_token: $VAULT_ROOT_TOKEN
vault_unseal_key: $VAULT_UNSEAL_KEY
vault_connection_url: https://vault:8200

## REDIS
redis_root_password: $REDIS_PASSWORD

## RABBITMQ
rabbit_password: $RABBIT_PASSWORD
rabbit_erlang_cookie: $RABBIT_ERLANG_COOKIE

## MINIO
minio_root_password: $MINIO_PASSWORD
minio_access_key: minioadmin

## GRAFANA
grafana_root_password: $GRAFANA_PASSWORD

## TRAEFIK (Basic Auth)
traefik_basicauth: admin:admin

## APPLICATION
jwt_secret_key: $JWT_SECRET
postgres_backup_encryption_pass: $BACKUP_ENCRYPTION

## IMGPROXY
imgproxy_key: $IMGPROXY_KEY
imgproxy_salt: $IMGPROXY_SALT

## TEMPO S3
# AWS credentials format for S3/MinIO integration
tempo_s3_credentials: See .secrets/tempo_s3_credentials.txt

## DEPLOYMENT CHECKLIST
- [ ] All secrets created successfully
- [ ] All networks created
- [ ] Volume directories created: /opt/containers/storages/*
- [ ] Node labels applied for constraints
- [ ] docker-stack-prod.yml reviewed
- [ ] Backup encryption key stored securely
- [ ] Vault unseal key stored in vault backend (not in Docker secrets)
- [ ] Database backups configured
EOF

log_info "Secrets reference saved to: $SECRETS_REFERENCE"

# ────────────────────────────────────────
# VERIFY ALL SECRETS
# ────────────────────────────────────────

log_info "Verifying created secrets..."
docker secret ls

# ────────────────────────────────────────
# SUMMARY
# ────────────────────────────────────────

echo ""
log_info "=========================================="
log_info "Production Secrets Initialization Complete"
log_info "=========================================="
echo ""
log_info "Created $(ls "$SECRETS_DIR"/*.txt 2>/dev/null | wc -l) local secret backups"
log_info "Secrets reference: $SECRETS_REFERENCE"
echo ""
log_warn "IMPORTANT: After verifying in secrets reference file:"
log_warn "  1. Store $SECRETS_REFERENCE in secure password manager"
log_warn "  2. Remove $SECRETS_DIR: rm -rf $SECRETS_DIR"
echo ""
log_info "Next steps:"
log_info "  1. Create volume directories:"
echo "     mkdir -p /opt/containers/storages/{postgres,redis,vault,minio,traefik,prometheus,grafana,loki,tempo}-data"
echo ""
log_info "  2. Apply node labels (if using multiple nodes):"
echo "     docker node update --label-add vault-node-1=true NODE_ID"
echo ""
log_info "  3. Deploy the stack:"
echo "     docker stack deploy --compose-file docker-stack-prod.yml production"
echo ""

