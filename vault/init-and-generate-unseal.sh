#!/bin/bash
set -e

echo "🔐 Initializing Vault Cluster..."
echo ""

# Wait for vault-1 to be ready (unsealed but not initialized)
echo "⏳ Waiting for vault-1 to be ready..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    # Check if we can connect to Vault and get a status response
    # vault status returns non-zero exit code when sealed, so we need to capture both stdout and exit code
    status=$(docker-compose exec -T vault-1 sh -c "export VAULT_ADDR='http://127.0.0.1:8200' && vault status -format=json 2>&1" || true)

    # Check if we got valid JSON output (meaning Vault is responding)
    if echo "$status" | jq -e . >/dev/null 2>&1; then
        initialized=$(echo "$status" | jq -r '.initialized // false')

        if [ "$initialized" = "false" ]; then
            echo "✅ Vault is ready for initialization"
            break
        elif [ "$initialized" = "true" ]; then
            echo "❌ Error: Vault is already initialized!"
            echo ""
            echo "If you want to re-initialize:"
            echo "  1. Run: task reset"
            echo "  2. Run: task bootstrap"
            exit 1
        fi
    else
        # Vault is not responding yet, keep waiting
        echo "⏳ Waiting for Vault to start (attempt $((attempt + 1))/$max_attempts)..."
    fi

    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Timeout waiting for vault-1 to be ready"
    echo ""
    echo "Check logs with: docker-compose logs vault-1"
    exit 1
fi

echo ""

# Initialize vault-1 and capture output
echo "🔑 Initializing Vault..."
INIT_OUTPUT=$(docker-compose exec -T vault-1 sh -c "export VAULT_ADDR='http://127.0.0.1:8200' && vault operator init -key-shares=5 -key-threshold=3 -format=json")

# Parse the JSON output
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
UNSEAL_KEY_4=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[3]')
UNSEAL_KEY_5=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[4]')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

echo "════════════════════════════════════════════════════════════════"
echo "⚠️  SAVE THESE CREDENTIALS SECURELY - THEY CANNOT BE RECOVERED!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Unseal Key 1: $UNSEAL_KEY_1"
echo "Unseal Key 2: $UNSEAL_KEY_2"
echo "Unseal Key 3: $UNSEAL_KEY_3"
echo "Unseal Key 4: $UNSEAL_KEY_4"
echo "Unseal Key 5: $UNSEAL_KEY_5"
echo ""
echo "Root Token: $ROOT_TOKEN"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""

# Save to a backup file
BACKUP_FILE="vault-credentials-$(date +%Y%m%d-%H%M%S).md"
cat > "$BACKUP_FILE" << EOF
Vault Cluster Initialization - $(date)
════════════════════════════════════════════════════════════════

Unseal Key 1: $UNSEAL_KEY_1
Unseal Key 2: $UNSEAL_KEY_2
Unseal Key 3: $UNSEAL_KEY_3
Unseal Key 4: $UNSEAL_KEY_4
Unseal Key 5: $UNSEAL_KEY_5

Root Token: $ROOT_TOKEN

════════════════════════════════════════════════════════════════
⚠️  Store this file securely and delete it from this location!
EOF

echo "✅ Credentials saved to: $BACKUP_FILE"
echo ""

# Generate unseal.sh for vault-1
echo "📝 Generating unseal.sh scripts..."

cat > vault-1/config/unseal.sh << EOF
#!/bin/sh
set -e
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator unseal $UNSEAL_KEY_1
vault operator unseal $UNSEAL_KEY_2
vault operator unseal $UNSEAL_KEY_3
echo "✅ Vault unsealed successfully"
EOF

chmod +x vault-1/config/unseal.sh

# Copy to vault-2
cp vault-1/config/unseal.sh vault-2/config/unseal.sh

# Copy to vault-3
cp vault-1/config/unseal.sh vault-3/config/unseal.sh

echo "✅ Created unseal.sh in vault-1/config/"
echo "✅ Created unseal.sh in vault-2/config/"
echo "✅ Created unseal.sh in vault-3/config/"
echo ""

# Also save JSON format for automation
echo "$INIT_OUTPUT" | jq '.' > vault-init-keys.json
echo "✅ Saved JSON format to: vault-init-keys.json"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "🎉 Initialization Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Secure the credentials file: $BACKUP_FILE"
echo "  2. Run: task setup-cluster"
echo "  3. Or manually:"
echo "     - task unseal-vault-1"
echo "     - task join-vault-2 && task unseal-vault-2"
echo "     - task join-vault-3 && task unseal-vault-3"
echo ""