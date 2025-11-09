ui = true
disable_mlock = true

api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "raft" {
  path    = "/vault/data"
  node_id = "vault"

  # For multi-node HA setup, each node can include one or more retry_join blocks
  # retry_join {
  #   leader_api_addr = "http://vault-1:8200"
  # }
  # retry_join {
  #   leader_api_addr = "http://vault-2:8200"
  # }
  # retry_join {
  #   leader_api_addr = "http://vault-3:8200"
  # }
}
