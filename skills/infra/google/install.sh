#!/usr/bin/env bash
# Deploy Google OAuth2 credentials + token to a host.
# Runs on the OPERATOR LAPTOP.
#
# Usage: install.sh <host>

set -euo pipefail

host="${1:-}"
[ -n "$host" ] || { echo "usage: $0 <host>" >&2; exit 1; }

HETZBOT_FLEET_ROOT="${HETZBOT_FLEET_ROOT:-$PWD}"
secrets_dir="$HETZBOT_FLEET_ROOT/.secrets/google"
creds="$secrets_dir/google-credentials.json"
token="$secrets_dir/google-token.json"

[ -f "$creds" ] || { echo "ERROR: $creds not found" >&2; exit 1; }
[ -f "$token" ] || { echo "ERROR: $token not found — run the auth flow first" >&2; exit 1; }

echo "[google] deploying credentials to $host"
ssh "root@$host" 'install -d -m 0700 /etc/hetzbot/google'
scp "$creds" "root@$host:/etc/hetzbot/google/google-credentials.json"
scp "$token" "root@$host:/etc/hetzbot/google/google-token.json"
ssh "root@$host" 'chmod 0600 /etc/hetzbot/google/*'

echo "[google] deployed to $host:/etc/hetzbot/google/"
