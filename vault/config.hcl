ui = true
disable_mlock = true

api_addr = "http://vault:8200"
cluster_addr = "http://vault:8201"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "postgresql" {
  connection_url = "postgres://vault_app:pjz22Q38atgkgij98x5cat79qwgn0xl@infra_postgres:5432/vaultdb?sslmode=disable"
}


# storage "raft" {
#   path    = "/vault/data"
#   node_id = "vault"
# }
