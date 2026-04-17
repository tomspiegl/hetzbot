#!/usr/bin/env bash
# Idempotently provision a Postgres DB + role + .env for a service.
# Runs on the HOST (installed at /opt/hetzbot/skills/infra/postgres/).
#
# Usage: install.sh <name>

set -euo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

name="${1:-}"
[ -n "$name" ] || fail "usage: $0 <name>"

env_file="/srv/$name/.env"
install -d -m 0750 "/srv/$name"

if [ -f "$env_file" ]; then
  log "$name: .env already exists — leaving in place"
  exit 0
fi

# Ensure the service user exists (deploy.sh may call us before useradd).
if ! id "$name" >/dev/null 2>&1; then
  useradd --system --home "/srv/$name" --shell /usr/sbin/nologin "$name"
fi

password=$(generate_password)

log "$name: creating Postgres role + database"
docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$name') THEN
    CREATE ROLE "$name" WITH LOGIN PASSWORD '$password';
  ELSE
    ALTER ROLE "$name" WITH LOGIN PASSWORD '$password';
  END IF;
END \$\$;
SELECT 'CREATE DATABASE "$name" OWNER "$name"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$name')\gexec
SQL

cat > "$env_file" <<EOF
DATABASE_URL=postgres://$name:$password@127.0.0.1:5432/$name
EOF
chmod 0640 "$env_file"
chown "root:$name" "$env_file"
chown "$name:$name" "/srv/$name"

log "$name: provisioned — $env_file written"
