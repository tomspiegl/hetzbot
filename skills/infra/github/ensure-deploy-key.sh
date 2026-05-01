#!/usr/bin/env bash
# Ensure a per-service GitHub deploy key is set up so the host can clone
# a private repo over SSH. Idempotent.
#
# Runs on the OPERATOR LAPTOP. Uses:
#   - ssh root@<host>     to generate the key on the host (as the service user)
#   - gh api              to register the key on GitHub
#
# Usage: ensure-deploy-key.sh <host> <service> <owner/repo>
#
# Convention:
#   - Each service has its own ed25519 keypair under /srv/<service>/.ssh/
#   - The public key is registered as a read-only deploy key on the repo,
#     titled "<host> (<service>)" so the operator can recognise it later.

set -euo pipefail

host="${1:-}"
service="${2:-}"
repo="${3:-}"
[ -n "$host" ] && [ -n "$service" ] && [ -n "$repo" ] \
  || { echo "usage: $0 <host> <service> <owner/repo>" >&2; exit 64; }

command -v gh >/dev/null \
  || { echo "[github] gh CLI not installed on operator laptop" >&2; exit 1; }

gh auth status >/dev/null 2>&1 \
  || { echo "[github] gh not authenticated — run 'gh auth login'" >&2; exit 1; }

title="$host ($service)"

# 1. Ensure keypair exists on the host as the service user.
pubkey=$(ssh "root@$host" "
  set -e
  install -d -m 0700 -o '$service' -g '$service' '/srv/$service/.ssh'
  if [ ! -f '/srv/$service/.ssh/id_ed25519' ]; then
    sudo -u '$service' ssh-keygen -t ed25519 -f '/srv/$service/.ssh/id_ed25519' -N '' -C '$service@$host' >/dev/null
  fi
  if [ ! -f '/srv/$service/.ssh/known_hosts' ]; then
    sudo -u '$service' ssh-keyscan -t ed25519 github.com 2>/dev/null > '/srv/$service/.ssh/known_hosts'
  fi
  cat '/srv/$service/.ssh/id_ed25519.pub'
")

# 2. Compare with deploy keys already on the repo. The 'key' field returned by
#    GitHub omits the comment, so we strip our local comment for matching.
local_key_data=$(awk '{print $1, $2}' <<<"$pubkey")
existing=$(gh api "repos/$repo/keys" --jq '.[] | "\(.id)\t\(.title)\t\(.key)"' 2>/dev/null || echo "")

if grep -qF "$local_key_data" <<<"$existing"; then
  echo "[github] deploy key already registered on $repo for $host ($service)"
  exit 0
fi

# 3. Register the key (read-only).
echo "[github] registering deploy key on $repo for $host ($service)"
gh api -X POST "repos/$repo/keys" \
  -f title="$title" \
  -f key="$pubkey" \
  -F read_only=true >/dev/null

# 4. Verify by SSH.
ssh "root@$host" "sudo -u '$service' ssh -T -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -i '/srv/$service/.ssh/id_ed25519' git@github.com" 2>&1 \
  | grep -q "successfully authenticated" \
  || { echo "[github] WARNING: deploy key added but SSH auth check failed (propagation lag?)" >&2; exit 0; }

echo "[github] deploy key verified for $host ($service)"
