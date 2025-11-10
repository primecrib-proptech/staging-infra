# ===================================================================
# Vault Configuration - Production-Ready Single-Node (Raft Storage)
# ===================================================================

ui = true
disable_mlock = true

# ---------------------------
# API Control
# ---------------------------
api_addr = "https://0.0.0.0:8200" # Use HTTPS
cluster_addr = "https://0.0.0.0:8201" # Use HTTPS

# ---------------------------
# Listener Configuration
# ---------------------------
listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = "false" # **CRITICAL: Enable TLS in production**
  tls_cert_file = "/vault/file/vault.crt"
  tls_key_file = "/vault/file/vault.key"
  tls_client_ca_file = "/vault/file/rootCA.crt"
}

# ---------------------------
# Storage Configuration (Raft)
# ---------------------------
storage "raft" {
  path = "/vault/file"
  node_id = "vault_node_1" # Unique ID for this node
  retry_join {
    leader_api_addr = "https://vault_node_1:8200" # Use HTTPS with TLS
  }
}

# ---------------------------
# Telemetry (optional metrics)
# ---------------------------
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = "false"
}
