#!/usr/bin/env bash
# Take a manual Hetzner Cloud snapshot of a host.
# Runs on the OPERATOR LAPTOP. Reads HCLOUD_TOKEN from env (.env).
#
# Usage: snapshot.sh <host> [description]

set -euo pipefail

host="${1:-}"
desc="${2:-hetzbot/$host/manual-$(date +%FT%H%M)}"
[ -n "$host" ] || { echo "usage: $0 <host> [description]" >&2; exit 64; }

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN not set in env — fleet .env not loaded?}"
: "${HETZBOT_FLEET_ROOT:=$PWD}"

log()  { printf '[snapshot] %s\n' "$*" >&2; }
fail() { printf '[snapshot] ERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. Resolve hcloud_id from tofu output ---
hosts_json=$(tofu -chdir="$HETZBOT_FLEET_ROOT/tofu" output -json hosts 2>/dev/null) \
  || fail "tofu output unavailable — run 'tofu apply' in the fleet repo first"

hcloud_id=$(jq -r --arg h "$host" '.[$h].hcloud_id // empty' <<<"$hosts_json")
[ -n "$hcloud_id" ] || fail "host '$host' not in tofu output, or missing hcloud_id (run tofu apply)"

log "host=$host hcloud_id=$hcloud_id desc=\"$desc\""

# --- 2. Optional pre-snapshot quiesce ---
if [ "${QUIESCE:-1}" = "1" ]; then
  log "quiescing: sync + pg_dump (set QUIESCE=0 to skip)"
  ssh "$host" sudo sync || true
  ssh "$host" 'test -x /opt/hetzbot/skills/infra/postgres/backup.sh && sudo /opt/hetzbot/skills/infra/postgres/backup.sh' || true
fi

# --- 3. Create the snapshot ---
log "calling Hetzner API create_image"
body=$(jq -nc --arg d "$desc" --arg h "$host" \
  '{type:"snapshot", description:$d, labels:{managed_by:"hetzbot", host:$h}}')

response=$(curl -sS -X POST \
  "https://api.hetzner.cloud/v1/servers/$hcloud_id/actions/create_image" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$body")

action_id=$(jq -r '.action.id // empty' <<<"$response")
image_id=$(jq -r '.image.id // empty' <<<"$response")
status=$(jq -r '.action.status // empty' <<<"$response")

[ -n "$action_id" ] || fail "no action_id in response: $response"
log "action_id=$action_id image_id=$image_id status=$status"

# --- 4. Poll ---
waited=0
while [ "$status" != "success" ]; do
  if [ "$status" = "error" ]; then
    err=$(jq -r '.action.error.message // "unknown"' <<<"$response")
    fail "snapshot action failed: $err"
  fi
  if [ "$waited" -gt 1800 ]; then
    log "still running at ${waited}s — continuing in background. Check with: hcloud action describe $action_id"
    break
  fi
  sleep 10
  waited=$(( waited + 10 ))
  response=$(curl -sS "https://api.hetzner.cloud/v1/actions/$action_id" \
    -H "Authorization: Bearer $HCLOUD_TOKEN")
  status=$(jq -r '.action.status // empty' <<<"$response")
  log "polling: status=$status waited=${waited}s"
done

log "done. image_id=$image_id"
echo "$image_id"
