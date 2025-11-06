ui = true
disable_mlock = true

storage "postgresql" {
  connection_url = "postgres://vaultuser:${VAULT_POSTGRES_PASSWORD}@postgres:5432/vaultdb?sslmode=disable"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://vault:8200"
cluster_addr = "http://vault:8201"

seal "shamir" {}
