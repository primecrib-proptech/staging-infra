#!/usr/bin/env bash
# Bootstrap Vault KV paths from local .secrets/ (same layout as init-production-secrets.sh)
set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/.." && pwd)/.secrets"
VAULT_ADDR="${VAULT_ADDR:-https://vault.platform-data.svc:8200}"
VAULT_TOKEN="${VAULT_TOKEN:?Set VAULT_TOKEN}"

log() { echo "[init-k8s-secrets] $*"; }

if [[ ! -d "$SECRETS_DIR" ]]; then
  log "Run init-production-secrets.sh first or create $SECRETS_DIR"
  exit 1
fi

vault kv put secret/platform/postgres \
  db_name="$(cat "$SECRETS_DIR/db_name.txt")" \
  db_user="$(cat "$SECRETS_DIR/db_user.txt")" \
  postgres_password="$(cat "$SECRETS_DIR/postgres_password.txt")" \
  db_app_password="$(cat "$SECRETS_DIR/db_app_password.txt")" \
  db_ro_password="$(cat "$SECRETS_DIR/db_ro_password.txt")"

vault kv put secret/platform/redis \
  redis_root_password="$(cat "$SECRETS_DIR/redis_root_password.txt")"

vault kv put secret/platform/rabbitmq \
  username=admin \
  rabbit_password="$(cat "$SECRETS_DIR/rabbit_password.txt")" \
  rabbit_erlang_cookie="$(cat "$SECRETS_DIR/rabbit_erlang_cookie.txt")"

vault kv put secret/platform/minio \
  minio_access_key="$(cat "$SECRETS_DIR/minio_access_key.txt")" \
  minio_root_password="$(cat "$SECRETS_DIR/minio_root_password.txt")"

vault kv put secret/platform/grafana \
  grafana_root_password="$(cat "$SECRETS_DIR/grafana_root_password.txt")"

vault kv put secret/platform/traefik \
  traefik_basicauth="$(cat "$SECRETS_DIR/traefik_basicauth.txt")"

vault kv put secret/platform/imgproxy \
  imgproxy_key="$(cat "$SECRETS_DIR/imgproxy_key.txt")" \
  imgproxy_salt="$(cat "$SECRETS_DIR/imgproxy_salt.txt")"

log "Platform secrets seeded. Configure apps/* paths before deploying workloads."
