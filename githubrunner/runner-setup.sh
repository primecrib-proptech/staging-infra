#!/bin/bash
set -e

# 1. Load the PAT from secrets
PAT=$(cat /run/secrets/github_pat)

# 2. Get a registration token from GitHub API using python (more reliable than jq if not installed)
echo "Fetching registration token from GitHub..."
JSON_RESPONSE=$(curl -sX POST -H "Authorization: token ${PAT}" \
    "https://api.github.com/repos/cyberstarsng/proptech-core-service/actions/runners/registration-token")

REG_TOKEN=$(echo "$JSON_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))")

if [ -z "$REG_TOKEN" ]; then
    echo "Error: Failed to get registration token. Response: $JSON_RESPONSE"
    exit 1
fi

# 3. Export for the underlying runner
export RUNNER_TOKEN=$REG_TOKEN

# 4. IMPORTANT: Use 'exec' to replace the shell process with the entrypoint script
# This keeps the container alive and the runner active.
echo "Starting runner..."
exec /entrypoint.sh