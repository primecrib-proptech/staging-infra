#!/bin/bash

# 1. Load the PAT from secrets
PAT=$(cat /run/secrets/github_pat)
export ACCESS_TOKEN=$PAT

cd /actions-runner

while true; do
    echo "----------------------------------------------------"
    echo "Fetching fresh registration token from GitHub..."
    
    JSON_RESPONSE=$(curl -sX POST -H "Authorization: token ${PAT}" \
        "https://api.github.com/repos/cyberstarsng/proptech-core-service/actions/runners/registration-token")

    REG_TOKEN=$(echo "$JSON_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))")

    if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" == "None" ]; then
        echo "Error: Failed to get token. Response: $JSON_RESPONSE"
        echo "Retrying in 10 seconds..."
        sleep 10
        continue
    fi

    export RUNNER_TOKEN=$REG_TOKEN

    echo "Configuring and starting runner listener..."
    # We call entrypoint.sh to handle the config, then run.sh to handle the execution
    # We use --once to ensure it cleans up properly before the next loop iteration
    /entrypoint.sh --once

    echo "Runner listener exited. Re-registering in 5 seconds..."
    sleep 5
done