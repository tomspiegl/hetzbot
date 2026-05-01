#!/usr/bin/env bash
# Deploy skills + selected services to a host.
# Runs on the OPERATOR LAPTOP; SSHes into the host over Tailscale.
#
# Usage:
#   skills/ops/deploy/deploy.sh <host>
#   skills/ops/deploy/deploy.sh <host> --dry-run

set -euo pipefail

# Framework lives here; fleet data (hosts.tfvars, services/) lives there.
HETZBOT_ROOT="${HETZBOT_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HETZBOT_FLEET_ROOT="${HETZBOT_FLEET_ROOT:-$PWD}"

cd "$HETZBOT_FLEET_ROOT"

host="${1:-}"
dry_run=0
[ -n "$host" ] || { echo "usage: $0 <host> [--dry-run]" >&2; exit 1; }
shift
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

log()  { printf '[deploy] %s\n' "$*" >&2; }
fail() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$dry_run" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*" >&2
  else
    eval "$@"
  fi
}

# --- 1. Resolve host config from tofu output (tofu lives in the fleet) ---
hosts_json=$(tofu -chdir="$HETZBOT_FLEET_ROOT/tofu" output -json hosts 2>/dev/null) \
  || fail "tofu output unavailable — run 'just apply' in the fleet repo first"

host_info=$(jq -e ".\"$host\"" <<<"$hosts_json") \
  || fail "host '$host' not in hosts.tfvars"

public=$(jq -r '.public' <<<"$host_info")
services=$(jq -r '.services[]' <<<"$host_info")
postgres_image=$(jq -r '.postgres_image // "pgvector/pgvector:pg16"' <<<"$host_info")
postgres_extra_pkgs=$(jq -r '.postgres_extra_pkgs // ""' <<<"$host_info")
postgres_partman_version=$(jq -r '.postgres_partman_version // ""' <<<"$host_info")

ssh_target="root@$host"

log "host=$host public=$public services=$(echo "$services" | tr '\n' ' ')"

# --- 2. Sanity checks (operator-side) ---
for svc in $services; do
  dir="services/$svc"
  [ -d "$dir" ] || fail "services/$svc/ missing"

  if [ -f "$dir/caddy.conf" ] && [ "$public" != "true" ]; then
    fail "services/$svc has caddy.conf but host $host is not public"
  fi
done

# --- 3. Rsync skills (framework) + services (fleet) to host ---
log "rsync skills/ (from $HETZBOT_ROOT) + services/ (from $HETZBOT_FLEET_ROOT) to $host"
run "rsync -az --delete '$HETZBOT_ROOT/skills/' $ssh_target:/opt/hetzbot/skills/"
run "ssh $ssh_target 'find /opt/hetzbot/skills -type f -name \"*.sh\" -exec chmod +x {} +'"

for svc in $services; do
  run "rsync -az --delete '$HETZBOT_FLEET_ROOT/services/$svc/' $ssh_target:/opt/hetzbot/services/$svc/"
done

# --- 4. Install universal infrastructure skills (docker, restic) ---
# These were cloud-init packages in v1; now they're explicit skills.
# Idempotent — exit fast on subsequent deploys.
run "ssh $ssh_target 'sudo /opt/hetzbot/skills/infra/docker/install.sh'"
run "ssh $ssh_target 'sudo /opt/hetzbot/skills/infra/restic/install.sh'"

# --- 5. Bring up stateful-infra skills (anything with a docker-compose.yml) ---
# Generate the Postgres superuser password on first boot; idempotent.
run "ssh $ssh_target 'sudo bash -c \"
  if [ ! -f /etc/hetzbot/postgres_superuser ]; then
    install -d -m 0700 /etc/hetzbot
    openssl rand -hex 32 > /etc/hetzbot/postgres_superuser
    chmod 0600 /etc/hetzbot/postgres_superuser
  fi
\"'"

for skill_dir in "$HETZBOT_ROOT"/skills/infra/*/; do
  skill=$(basename "$skill_dir")
  case "$skill" in
    deploy|add-service|docker|restic|caddy) continue ;;
  esac
  compose="$skill_dir/docker-compose.yml"
  [ -f "$compose" ] || continue
  log "skill:$skill — docker compose up"
  if [ "$skill" = "postgres" ]; then
    run "ssh $ssh_target 'cd /opt/hetzbot/skills/infra/$skill && sudo POSTGRES_IMAGE=\"$postgres_image\" POSTGRES_EXTRA_PKGS=\"$postgres_extra_pkgs\" POSTGRES_PARTMAN_VERSION=\"$postgres_partman_version\" docker compose up -d --build --wait'"
  else
    run "ssh $ssh_target 'cd /opt/hetzbot/skills/infra/$skill && sudo docker compose up -d --wait'"
  fi
done

# --- 5. Deploy each native service ---
for svc in $services; do
  log "deploying $svc"

  src_file="services/$svc/source"
  [ -f "$src_file" ] || fail "services/$svc/source missing"
  source_url=$(tr -d '[:space:]' < "$src_file")

  # If the repo is fetched over SSH (private GitHub), make sure the host
  # has a deploy key registered before install-service.sh tries to clone.
  if [[ "$source_url" =~ ^git@github\.com:([^/]+/[^.]+)\.git ]]; then
    repo="${BASH_REMATCH[1]}"
    run "bash '$HETZBOT_ROOT/skills/infra/github/ensure-deploy-key.sh' '$host' '$svc' '$repo'"
  fi

  run "ssh $ssh_target 'sudo /opt/hetzbot/skills/ops/deploy/install-service.sh $svc \"$source_url\"'"
done

# --- 6. Caddy (public hosts only) — install + assemble ---
if [ "$public" = "true" ]; then
  log "ensuring caddy installed + reassembling /etc/caddy/Caddyfile"
  run "ssh $ssh_target 'sudo /opt/hetzbot/skills/infra/caddy/install.sh'"
  run "ssh $ssh_target 'sudo /opt/hetzbot/skills/infra/caddy/assemble.sh'"
fi

log "done"
