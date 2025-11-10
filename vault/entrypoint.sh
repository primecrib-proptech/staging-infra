#!/usr/bin/env bash
set -e

# ==============================
# VARIABLES
# ==============================
VAULT_ADDR="http://127.0.0.1:8200"
KEY_SHARES=5
KEY_THRESHOLD=3

# ==============================
# FUNCTIONS (Tasks)
# ==============================

check() {
  echo "🔍 Checking prerequisites..."
  ./check-prerequisites.sh
}

up() {
  echo "🚀 Starting Vault cluster..."
  docker-compose up -d
}

down() {
  echo "🛑 Stopping Vault cluster..."
  docker-compose down
}

clean() {
  echo "🧹 Cleaning up containers, networks, and volumes..."
  docker-compose down -v
}

reset() {
  echo "⚠️  This will delete ALL Vault data. Continue? (y/n)"
  read -r confirm
  if [[ "$confirm" != "y" ]]; then
    echo "❌ Cancelled."
    exit 1
  fi

  down
  docker-compose down -v

  echo "🗑️  Removing Raft data..."
  rm -rf vault-{1..3}/data/raft/*
  rm -f vault-{1..3}/data/vault.db

  echo "🗑️  Removing generated unseal scripts..."
  echo "✅ Reset complete! You can now run './entrypoint.sh bootstrap' for a fresh start."
}

init() {
  echo "🚧 Initializing Vault-1..."
  if ! docker-compose ps vault-1 | grep -q "Up"; then
    echo "❌ vault-1 is not running. Run './entrypoint.sh up' first."
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required but not installed. Install it first."
    exit 1
  fi

  ./init-and-generate-unseal.sh
}

unseal_vault_1() {
  echo "🔓 Unsealing vault-1..."
  docker-compose exec vault-1 sh /vault/config/unseal.sh
}

unseal_vault_2() {
  echo "🔓 Unsealing vault-2..."
  docker-compose exec vault-2 sh /vault/config/unseal.sh
}

unseal_vault_3() {
  echo "🔓 Unsealing vault-3..."
  docker-compose exec vault-3 sh /vault/config/unseal.sh
}

join_vault_2() {
  echo "🤝 Joining vault-2 to Raft cluster..."
  docker-compose exec vault-2 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault operator raft join http://vault-1:8200"
}

join_vault_3() {
  echo "🤝 Joining vault-3 to Raft cluster..."
  docker-compose exec vault-3 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault operator raft join http://vault-1:8200"
}

setup_cluster() {
  echo "⚙️  Setting up cluster..."
  unseal_vault_1
  join_vault_2
  unseal_vault_2
  join_vault_3
  unseal_vault_3
}

bootstrap() {
  echo "🚀 Bootstrapping Vault cluster..."
  up
  echo "⏳ Waiting for containers to be ready (15 seconds)..."
  sleep 15
  init
  echo ""
  echo "📋 Credentials saved! Review them above."
  echo "Press Enter to continue with cluster setup..."
  read _
  setup_cluster
  echo ""
  echo "✅ Bootstrap complete!"
}

status() {
  echo "=== Vault-1 Status ==="
  docker-compose exec vault-1 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" || true
  echo ""
  echo "=== Vault-2 Status ==="
  docker-compose exec vault-2 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" || true
  echo ""
  echo "=== Vault-3 Status ==="
  docker-compose exec vault-3 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" || true
}

cluster_check() {
  echo "========================================================================"
  echo "VAULT CLUSTER HEALTH CHECK"
  echo "========================================================================"
  echo ""
  echo "[1] Container Status:"
  docker-compose ps
  echo ""
  echo "[2] Vault-1 Status:"
  docker-compose exec vault-1 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" || true
  echo ""
  echo "[3] Vault-2 Status:"
  docker-compose exec vault-2 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" || true
  echo ""
  echo "[4] Vault-3 Status:"
  docker-compose exec vault-3 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" || true
  echo ""
  echo "[5] Raft Cluster Members:"
  docker-compose exec vault-1 sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault operator raft list-peers" || true
  echo ""
  echo "[6] Load Balancer Health Check:"
  curl -s ${VAULT_ADDR}/v1/sys/health | jq '.' || true
  echo ""
  echo "========================================================================"
  echo "CLUSTER CHECK COMPLETE"
  echo "========================================================================"
}

quick_check() {
  echo "QUICK CLUSTER STATUS:"
  echo "---"
  for i in 1 2 3; do
    echo "Vault-${i}:"
    docker-compose exec vault-${i} sh -c "export VAULT_ADDR='${VAULT_ADDR}' && vault status" | grep -E "Sealed|HA Mode" || true
    echo ""
  done
}

monitor_logs() {
  docker-compose logs -f vault-unsealer
}

monitor_status() {
  docker-compose ps vault-unsealer
  echo ""
  echo "Recent monitor activity:"
  docker-compose logs vault-unsealer | tail -15
}

logs() {
  docker-compose logs -f
}

logs_vault_1() {
  docker-compose logs -f vault-1
}

logs_vault_2() {
  docker-compose logs -f vault-2
}

logs_vault_3() {
  docker-compose logs -f vault-3
}

shell_vault_1() {
  docker-compose exec vault-1 sh
}

shell_vault_2() {
  docker-compose exec vault-2 sh
}

shell_vault_3() {
  docker-compose exec vault-3 sh
}

restart() {
  down
  up
  echo "Waiting for containers to start..."
  sleep 5
}

# ==============================
# MAIN MENU
# ==============================

case "$1" in
  check|up|down|clean|reset|init|unseal_vault_1|unseal_vault_2|unseal_vault_3|join_vault_2|join_vault_3|setup_cluster|bootstrap|status|cluster_check|quick_check|monitor_logs|monitor_status|logs|logs_vault_1|logs_vault_2|logs_vault_3|shell_vault_1|shell_vault_2|shell_vault_3|restart)
    "$@"
    ;;
  *)
    echo "Usage: $0 {check|up|down|clean|reset|init|unseal_vault_1|unseal_vault_2|unseal_vault_3|join_vault_2|join_vault_3|setup_cluster|bootstrap|status|cluster_check|quick_check|monitor_logs|monitor_status|logs|logs_vault_1|logs_vault_2|logs_vault_3|shell_vault_1|shell_vault_2|shell_vault_3|restart}"
    exit 1
    ;;
esac
