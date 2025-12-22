#!/bin/bash
set -e

# 1. Load the PAT from secrets
PAT=$(cat /run/secrets/github_pat)

# 2. Get a registration token from GitHub API
echo "Fetching registration token from GitHub..."
REG_TOKEN=$(curl -sX POST -H "Authorization: token ${PAT}" \
    "https://api.github.com/repos/cyberstarsng/proptech-core-service/actions/runners/registration-token" \
    | jq -r .token)

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "Error: Failed to get registration token. Check your PAT and repository URL."
    exit 1
fi

# 3. Export variables for the underlying runner software
export RUNNER_TOKEN=$REG_TOKEN
export ACCESS_TOKEN=$PAT

# 4. Execute the image's original entrypoint
exec /entrypoint.sh