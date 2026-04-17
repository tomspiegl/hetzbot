#!/usr/bin/env bash
# Audit Node runtime + npm safety. Read-only. Runs on HOST.
# Invoked by skills/hetzner/review-host/review.sh.

set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

# --- Is any service on this host a Node service? ---
needs_node=0
for repo in /srv/*/repo; do
  [ -f "$repo/package-lock.json" ] && needs_node=1
done

# --- Node binary present? ---
if ! command -v node >/dev/null 2>&1; then
  if [ "$needs_node" = 1 ]; then
    finding HIGH runtime:node "services need Node but \`node\` is not installed"
  else
    finding OK runtime:node "not installed (no Node services on host)"
  fi
  exit 0
fi

node_v=$(node --version 2>/dev/null || echo "?")
finding OK runtime:node "installed: $node_v"

# LTS majors as of 2026: 20, 22, 24. <20 = EOL.
case "$node_v" in
  v20.*|v22.*|v24.*) : ;;
  v18.*|v16.*|v14.*|v12.*) finding HIGH runtime:node "version $node_v is end-of-life (upgrade major)" ;;
  *) finding LOW  runtime:node "version $node_v is non-LTS or unknown" ;;
esac

# --- /etc/npmrc lockdown ---
if [ ! -f /etc/npmrc ]; then
  finding HIGH runtime:node "/etc/npmrc missing — ignore-scripts not enforced host-wide"
else
  grep -qE '^\s*ignore-scripts\s*=\s*true' /etc/npmrc \
    && finding OK runtime:node "/etc/npmrc: ignore-scripts=true" \
    || finding HIGH runtime:node "/etc/npmrc lacks ignore-scripts=true (postinstall attack vector open)"

  grep -qE '^\s*audit-level\s*=' /etc/npmrc \
    && finding OK runtime:node "/etc/npmrc: audit-level set" \
    || finding MEDIUM runtime:node "/etc/npmrc lacks audit-level setting"

  grep -qE '^\s*fund\s*=\s*false' /etc/npmrc \
    && finding OK runtime:node "/etc/npmrc: fund=false" \
    || finding LOW runtime:node "/etc/npmrc lacks fund=false (noise only)"
fi

# --- unattended-upgrades covers NodeSource? ---
if [ -f /etc/apt/apt.conf.d/51unattended-upgrades-nodesource ] \
   || grep -qr 'nodesource' /etc/apt/apt.conf.d/ 2>/dev/null; then
  finding OK runtime:node "unattended-upgrades covers NodeSource"
else
  finding MEDIUM runtime:node "NodeSource not in unattended-upgrades allowlist (Node security patches skipped)"
fi

# --- Per-service lockfile present + in sync (best-effort) ---
for repo in /srv/*/repo; do
  svc=$(basename "$(dirname "$repo")")
  if [ -f "$repo/package.json" ] && [ ! -f "$repo/package-lock.json" ]; then
    finding HIGH runtime:node "$svc: package.json without package-lock.json (deploy should have refused this)"
  fi
done
