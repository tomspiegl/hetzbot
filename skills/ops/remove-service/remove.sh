#!/usr/bin/env bash
# Remove a service from the host. Runs on HOST as root.
# Called by the remove-service skill after the operator confirms.
#
# Usage: remove.sh <name>

set -euo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

name="${1:-}"
[ -n "$name" ] || fail "usage: $0 <name>"

# --- 1. Stop + disable systemd units ---
if systemctl list-unit-files | grep -q "^$name.timer"; then
  log "$name: disabling timer"
  systemctl disable --now "$name.timer" || true
fi
if systemctl list-unit-files | grep -q "^$name.service"; then
  log "$name: stopping + disabling unit"
  systemctl disable --now "$name.service" || true
fi

rm -f "/etc/systemd/system/$name.service" \
      "/etc/systemd/system/$name.timer"
rm -rf "/etc/systemd/system/$name.service.d"
systemctl daemon-reload

# --- 2. Drop DB + role (Postgres) ---
if docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
  log "$name: dropping DB + role"
  docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL || true
DROP DATABASE IF EXISTS "$name" WITH (FORCE);
DROP ROLE IF EXISTS "$name";
SQL
fi

# --- 3. Remove on-host service dir ---
rm -rf "/srv/$name"
rm -rf "/opt/hetzbot/services/$name"

# --- 4. Remove the service user (no-op if already gone) ---
if id "$name" >/dev/null 2>&1; then
  userdel "$name" 2>/dev/null || true
fi

log "$name: removed from host"
