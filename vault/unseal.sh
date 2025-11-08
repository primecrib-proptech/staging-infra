##!/bin/sh
#set -e
#
#UNSEAL_KEY=$(cat /run/secrets/vault_unseal_key)
#ROOT_TOKEN=$(cat /run/secrets/vault_root_token)
#
#echo "Attempting to unseal Vault..."
#vault operator unseal $UNSEAL_KEY || true
#
## Wait until Vault is unsealed
#until vault status | grep -q 'Initialized.*true' && vault status | grep -q 'Sealed.*false'; do
#  echo "Waiting for Vault to unseal..."
#  sleep 3
#done
#
#echo "Vault unsealed successfully!"
#vault login $ROOT_TOKEN


#!/bin/sh
set -e

# Read pre-generated secrets
UNSEAL_KEY_FILE=/run/secrets/vault_unseal_key
ROOT_TOKEN_FILE=/run/secrets/vault_root_token

if [ ! -f "$UNSEAL_KEY_FILE" ] || [ ! -f "$ROOT_TOKEN_FILE" ]; then
    echo "ERROR: Vault unseal key or root token secret missing!"
    exit 1
fi

UNSEAL_KEY=$(cat "$UNSEAL_KEY_FILE")
ROOT_TOKEN=$(cat "$ROOT_TOKEN_FILE")

# Unseal Vault (idempotent)
vault operator unseal "$UNSEAL_KEY" || true

# Wait until Vault is unsealed
until vault status | grep -q 'Sealed.*false'; do
    echo "Waiting for Vault to unseal..."
    sleep 2
done

echo "Vault unsealed successfully!"
vault login "$ROOT_TOKEN" >/dev/null 2>&1
echo "Logged in with root token"
