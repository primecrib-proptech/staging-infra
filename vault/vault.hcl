# ===================================================================
# Vault Configuration - Production-Ready Single-Node (Raft Storage)
# ===================================================================

ui = true
disable_mlock = true

# ---------------------------
# API Control
# ---------------------------
api_addr = "https://infra_vault:8200" # Use HTTPS
cluster_addr = "https://infra_vault:8201" # Use HTTPS

# ---------------------------
# Listener Configuration
# ---------------------------
listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"

  tls_disable = 0
  tls_cert_file = "/vault/certs/vault.crt"
  tls_key_file = "/vault/certs/vault.key"
  tls_client_ca_file = "/vault/certs/rootCA.crt"
}

# ---------------------------
# Storage Configuration (Raft)
# ---------------------------
storage "raft" {
  path = "/vault/data"
  node_id = "vault"

  retry_join {
    leader_api_addr = "https://infra_vault:8200"
  }
}

# ---------------------------
# Telemetry (optional metrics)
# ---------------------------
# telemetry {
#   prometheus_retention_time = "30s"
#   disable_hostname = "false"
# }
