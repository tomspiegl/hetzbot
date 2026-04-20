#!/usr/bin/env bash
# Check which .env variables are set vs missing for a fleet.
# Never prints secret values — only "set" or "MISSING".
#
# Runs on the OPERATOR LAPTOP.
# Usage: check-env.sh <fleet-path>

set -euo pipefail

fleet_path="${1:-.}"
env_file="$fleet_path/.env"

if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file not found — run 'cp .env.example .env' first" >&2
  exit 1
fi

set -a; source "$env_file"; set +a

# Required for all fleets.
required=(
  HETZBOT_ROOT
  HCLOUD_TOKEN
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  OS_REGION
  OS_ENDPOINT
  OS_BUCKET
  RESTIC_PASSWORD
  CONSOLE_ROOT_PASSWORD
)

# Optional — only needed in certain configurations.
optional=(
  DOMAIN
  TAILSCALE_AUTHKEY
)

missing=0

echo "=== required ==="
for var in "${required[@]}"; do
  val="${!var:-}"
  if [ -n "$val" ]; then
    echo "  $var: set"
  else
    echo "  $var: MISSING"
    missing=$((missing + 1))
  fi
done

echo ""
echo "=== optional ==="
for var in "${optional[@]}"; do
  val="${!var:-}"
  if [ -n "$val" ]; then
    echo "  $var: set"
  else
    echo "  $var: not set"
  fi
done

echo ""
if [ "$missing" -gt 0 ]; then
  echo "$missing required variable(s) missing"
  exit 1
else
  echo "all required variables set"
fi
