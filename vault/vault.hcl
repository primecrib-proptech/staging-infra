listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = "false" # **CRITICAL: Enable TLS in production**
  tls_cert_file = "/vault/file/vault.crt"
  tls_key_file = "/vault/file/vault.key"
  tls_client_ca_file = "/vault/file/rootCA.crt"
}

storage "raft" {
  path = "/vault/file"
  node_id = "vault_node_1" # Unique ID for this node
  retry_join {
    leader_api_addr = "https://vault_node_1:8200" # Use HTTPS with TLS
  }
  # For a multi-node cluster, add retry_join stanzas for other nodes:
  # retry_join {
  #   leader_api_addr = "https://vault_node_2:8200"
  # }
}

api_addr = "https://0.0.0.0:8200" # Use HTTPS
cluster_addr = "https://0.0.0.0:8201" # Use HTTPS

# Other essential production settings:
disable_mlock = "false" # Keep mlock enabled for security
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = "false"
}
