#!/bin/sh

# ===================================================================
# Vault Auto-Unseal Script
# ===================================================================
# This script automatically unseals Vault using provided unseal keys
# Usage: ./auto-unseal.sh
# ===================================================================

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
MAX_RETRIES=30
RETRY_INTERVAL=5
UNSEAL_KEYS_FILE="${UNSEAL_KEYS_FILE:-/vault/config/unseal-keys.txt}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Wait for Vault to be available
wait_for_vault() {
    log_info "Waiting for Vault to be available at ${VAULT_ADDR}..."
    retries=0

    while [ $retries -lt $MAX_RETRIES ]; do
        if vault status >/dev/null 2>&1 || [ $? -eq 2 ]; then
            log_info "Vault is available"
            return 0
        fi

        retries=$((retries + 1))
        log_warn "Vault not ready yet (attempt $retries/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done

    log_error "Vault did not become available after $MAX_RETRIES attempts"
    return 1
}

# Check if Vault is sealed
is_vault_sealed() {
    status=$(vault status -format=json 2>/dev/null | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ')

    if [ "$status" = "true" ]; then
        return 0  # Sealed
    elif [ "$status" = "false" ]; then
        return 1  # Unsealed
    else
        return 2  # Unable to determine
    fi
}

# Unseal Vault with provided keys
unseal_vault() {
    log_info "Starting Vault unseal process..."

    # Check if unseal keys file exists
    if [ ! -f "$UNSEAL_KEYS_FILE" ]; then
        log_error "Unseal keys file not found at: $UNSEAL_KEYS_FILE"
        log_error "Please create the file with one unseal key per line"
        return 1
    fi

    # Read unseal keys from file
    key_count=0
    while IFS= read -r unseal_key || [ -n "$unseal_key" ]; do
        # Skip empty lines and comments
        case "$unseal_key" in
            ''|'#'*) continue ;;
        esac

        key_count=$((key_count + 1))
        log_info "Applying unseal key $key_count..."

        if vault operator unseal "$unseal_key" >/dev/null 2>&1; then
            log_info "Unseal key $key_count applied successfully"
        else
            log_error "Failed to apply unseal key $key_count"
            return 1
        fi

        # Check if Vault is now unsealed
        if ! is_vault_sealed; then
            log_info "✓ Vault successfully unsealed!"
            return 0
        fi
    done < "$UNSEAL_KEYS_FILE"

    if [ $key_count -eq 0 ]; then
        log_error "No valid unseal keys found in $UNSEAL_KEYS_FILE"
        return 1
    fi

    # Final check
    if is_vault_sealed; then
        log_error "Vault is still sealed after applying $key_count keys"
        log_error "You may need more unseal keys to reach the threshold"
        return 1
    fi

    return 0
}

# Main execution
main() {
    log_info "Vault Auto-Unseal Script Started"
    log_info "Target: ${VAULT_ADDR}"

    # Wait for Vault to be available
    if ! wait_for_vault; then
        exit 1
    fi

    # Check seal status
    if is_vault_sealed; then
        log_warn "Vault is SEALED - proceeding with unseal"
        if unseal_vault; then
            log_info "✓ Vault auto-unseal completed successfully"
            exit 0
        else
            log_error "✗ Vault auto-unseal failed"
            exit 1
        fi
    else
        log_info "✓ Vault is already UNSEALED - no action needed"
        exit 0
    fi
}

# Run main function
main