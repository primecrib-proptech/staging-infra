#!/bin/sh
set -e

UNSEAL_KEY=$(cat /run/secrets/vault_unseal_key)
ROOT_TOKEN=$(cat /run/secrets/vault_root_token)

echo "Attempting to unseal Vault..."
vault operator unseal $UNSEAL_KEY || true

# Wait until Vault is unsealed
until vault status | grep -q 'Initialized.*true' && vault status | grep -q 'Sealed.*false'; do
  echo "Waiting for Vault to unseal..."
  sleep 3
done

echo "Vault unsealed successfully!"
vault login $ROOT_TOKEN
