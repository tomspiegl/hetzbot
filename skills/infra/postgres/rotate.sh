#!/usr/bin/env bash
# Rotate a service's Postgres password. Idempotent.
# Runs on the HOST. Usage: rotate.sh <name>

set -euo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

name="${1:-}"
[ -n "$name" ] || fail "usage: $0 <name>"

env_file="/srv/$name/.env"
[ -f "$env_file" ] || fail "$env_file not found — service not provisioned?"

password=$(generate_password)

log "$name: rotating Postgres password"
docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE "$name" WITH PASSWORD '$password';
SQL

# Preserve any other keys the service may have added to its .env.
tmp=$(mktemp)
grep -v '^DATABASE_URL=' "$env_file" > "$tmp" || true
echo "DATABASE_URL=postgres://$name:$password@127.0.0.1:5432/$name" >> "$tmp"
mv "$tmp" "$env_file"
chmod 0640 "$env_file"
chown "root:$name" "$env_file"

log "$name: restarting unit"
systemctl restart "$name"

log "$name: rotated"
