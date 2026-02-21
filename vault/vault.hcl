# ===================================================================
# Vault Configuration - HA-ready Raft baseline
# (works with single instance now; supports future multi-node migration)
# ===================================================================

ui = true
disable_mlock = false

# ---------------------------
# API / Cluster addresses
# ---------------------------
# Do not use loopback for HA. These addresses must be reachable by peers/clients.
# Single-node today still works with this service DNS.
api_addr = "https://vault:8200"
cluster_addr = "https://vault:8201"

# ---------------------------
# Listener Configuration
# ---------------------------
listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"

  tls_disable = 0
  tls_cert_file    = "/vault/cert/vault.crt"
  tls_key_file     = "/vault/cert/vault.key"
  tls_client_ca_file = "/vault/cert/vault-ca.pem"
}

# ---------------------------
# Storage Configuration (Raft)
# ---------------------------
storage "raft" {
  path = "/vault/data"

  # Keep node_id unset so Vault persists/generated unique ID per data dir.
  # For multi-node HA, each replica must have a unique persistent data volume.

  # Future HA join examples (enable when adding additional nodes):
  # retry_join {
  #   leader_api_addr = "https://vault-1:8200"
  # }
  # retry_join {
  #   leader_api_addr = "https://vault-2:8200"
  # }
  # retry_join {
  #   leader_api_addr = "https://vault-3:8200"
  # }
}

# ---------------------------
# Telemetry (optional metrics)
# ---------------------------
telemetry {
  prometheus_retention_time = "24h"
  disable_hostname = false
}
