# ===================================================================
# Vault Configuration - Production-Ready Single-Node (Raft Storage)
# ===================================================================

ui = true
disable_mlock = true


# ---------------------------
# API Control
# ---------------------------
api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

# ---------------------------
# Listener Configuration
# ---------------------------
listener "tcp" {
  address     = "0.0.0.0:8200"
  cluster_addr = "http://0.0.0.0:8201"
  tls_disable = 1
}

# ---------------------------
# Storage Configuration (Raft)
# ---------------------------
storage "raft" {
  path    = "/vault/file"
  node_id = "vault"
}

# ---------------------------
# Telemetry (optional metrics)
# ---------------------------
telemetry {
  prometheus_retention_time = "24h"
  disable_hostname = true
}