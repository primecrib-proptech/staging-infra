# ===================================================================
# Vault Configuration - HA-ready Raft baseline
# (works with single instance now; supports future multi-node migration)
# ===================================================================

ui = true
disable_mlock = false

# ---------------------------
# API / Cluster addresses
# ---------------------------
# Single-node hotfix: keep API + cluster local to avoid self-forwarding through Traefik.
api_addr = "https://vault-2:8200"
cluster_addr = "https://vault-2:8201"

# ---------------------------
# Listener Configuration
# ---------------------------
listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"

  tls_disable = 0
  tls_cert_file    = "/vault/certs/vault.crt"
  tls_key_file     = "/vault/certs/vault.key"
  tls_client_ca_file = "/vault/certs/vault-ca.pem"
}

# ---------------------------
# Storage Configuration (Raft)
# ---------------------------
storage "raft" {
  path = "/vault/data"

  # Single-node hotfix: match existing raft peer identity.
  # Without this, Vault can generate a random LocalID and fail with
  # "not part of stable configuration" + forwarded RPC errors.

   node_id = "vault-2"

  # Future HA join examples (enable when adding additional nodes):
  retry_join {
    leader_api_addr = "https://vault-1:8200"
  }
  retry_join {
     leader_api_addr = "https://vault-2:8200"
  }
  retry_join {
     leader_api_addr = "https://vault-3:8200"
   }
}



# ---------------------------
# Telemetry (optional metrics)
# ---------------------------
telemetry {
  prometheus_retention_time = "24h"
}
