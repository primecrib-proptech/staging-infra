#!/bin/sh
# 1) Create a PAT in GitHub with appropriate scope:
# - For repo runner registration: "repo" is typically needed for private repos.
# Export it locally (do NOT paste it into chat logs).
export GITHUB_PAT=$(cat /run/secrets/github_pat)

# 2) Get a short-lived runner registration token for the repo:
export OWNER="cyberstarsng"
export REPO="proptech-core-service"

RUNNER_TOKEN=$(curl -fsSL -X POST \
  -H "Authorization: token ${GITHUB_PAT}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/actions/runners/registration-token" \
  | python3 -c 'import sys, json; print(json.load(sys.stdin)["token"])')

# 3) Create/update the Docker Swarm secret
printf "%s" "${RUNNER_TOKEN}" | docker secret rm github_runner_token 2>/dev/null || true
printf "%s" "${RUNNER_TOKEN}" | docker secret create github_runner_token -
