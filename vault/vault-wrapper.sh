#!/bin/sh

# ===================================================================
# Vault Wrapper Script - Starts Vault and Auto-Unseals
# ===================================================================

set -e

echo "[WRAPPER] Starting Vault server in background..."
vault server -config=/vault/config/vault.hcl &
VAULT_PID=$!

echo "[WRAPPER] Vault server started with PID: $VAULT_PID"
echo "[WRAPPER] Waiting 10 seconds for Vault to initialize..."
sleep 10

echo "[WRAPPER] Running auto-unseal script..."
if /vault/scripts/auto-unseal.sh; then
    echo "[WRAPPER] Auto-unseal successful"
else
    echo "[WRAPPER] Auto-unseal failed, but Vault is running"
fi

echo "[WRAPPER] Monitoring Vault process..."
wait $VAULT_PID