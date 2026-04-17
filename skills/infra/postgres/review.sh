#!/usr/bin/env bash
# Audit shared Postgres. Read-only. Runs on HOST.
# Invoked by the review-host orchestrator.
set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

# --- Is Postgres expected on this host? ---
if [ ! -f /opt/hetzbot/skills/infra/postgres/docker-compose.yml ]; then
  exit 0   # skill not deployed here
fi

# Enumerate service users from /srv (proxy for "deployed services").
mapfile -t deployed < <(find /srv -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)

# --- Docker running at all? ---
if ! command -v docker >/dev/null 2>&1; then
  finding CRITICAL postgres "docker not installed"
  exit 0
fi

# --- Container health ---
if ! docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
  if [ ${#deployed[@]} -gt 0 ]; then
    finding CRITICAL postgres "container not running but services are deployed"
  else
    finding LOW postgres "container not running (no services yet)"
  fi
  exit 0
fi

health=$(docker inspect postgres --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
case "$health" in
  healthy) finding OK postgres "container healthy" ;;
  starting) finding MEDIUM postgres "container still starting" ;;
  unhealthy) finding CRITICAL postgres "container unhealthy" ;;
  *) finding HIGH postgres "container health=$health" ;;
esac

# --- pg_isready ---
if docker exec postgres pg_isready -U postgres >/dev/null 2>&1; then
  finding OK postgres "pg_isready succeeds"
else
  finding HIGH postgres "pg_isready fails"
fi

# --- DB per deployed service ---
mapfile -t dbs < <(docker exec postgres psql -U postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1')" 2>/dev/null || true)

for svc in "${deployed[@]}"; do
  found=0
  for db in "${dbs[@]}"; do
    [ "$db" = "$svc" ] && { found=1; break; }
  done
  if [ "$found" = 1 ]; then
    finding OK postgres "db '$svc' exists"
  else
    finding HIGH postgres "no DB named '$svc' (service deployed but not provisioned?)"
  fi
done

# --- Listener is 127.0.0.1 only ---
port_binding=$(docker port postgres 2>/dev/null | head -1 || true)
if echo "$port_binding" | grep -q '^5432/tcp -> 127.0.0.1:'; then
  finding OK postgres "bound to 127.0.0.1 only"
elif echo "$port_binding" | grep -q '0.0.0.0'; then
  finding CRITICAL postgres "container publishing on 0.0.0.0 (should be 127.0.0.1)"
fi
