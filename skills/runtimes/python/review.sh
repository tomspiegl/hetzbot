#!/usr/bin/env bash
# Audit Python runtime + uv + lockfile hygiene. Read-only. Runs on HOST.
set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

# --- Does any service on this host need Python? ---
needs_python=0
for repo in /srv/*/repo; do
  [ -f "$repo/uv.lock" ] && needs_python=1
  [ -f "$repo/pyproject.toml" ] && needs_python=1
done

# --- uv binary present? ---
if ! command -v uv >/dev/null 2>&1; then
  if [ "$needs_python" = 1 ]; then
    finding HIGH runtime:python "services need Python but \`uv\` is not installed"
  else
    finding OK runtime:python "uv not installed (no Python services on host)"
  fi
  exit 0
fi

uv_v=$(uv --version 2>/dev/null | awk '{print $2}')
finding OK runtime:python "uv installed: $uv_v"

# --- Per-service lockfile hygiene ---
for repo in /srv/*/repo; do
  svc=$(basename "$(dirname "$repo")")

  if [ -f "$repo/pyproject.toml" ]; then
    if [ ! -f "$repo/uv.lock" ]; then
      finding HIGH runtime:python "$svc: pyproject.toml without uv.lock (no hash verification)"
    else
      finding OK runtime:python "$svc: uv.lock present"
    fi
  fi

  if [ -f "$repo/requirements.txt" ] && [ ! -f "$repo/uv.lock" ]; then
    # Raw requirements.txt is allowed only if it carries hashes.
    if grep -qE '\-\-hash=' "$repo/requirements.txt" 2>/dev/null; then
      finding LOW runtime:python "$svc: requirements.txt with --hash= (acceptable but prefer uv.lock)"
    else
      finding MEDIUM runtime:python "$svc: requirements.txt without hashes (no supply-chain verification)"
    fi
  fi

  # .venv should live inside the service dir (not system-wide)
  if [ -d "$repo/.venv" ]; then
    venv_owner=$(stat -c '%U' "$repo/.venv" 2>/dev/null || echo "?")
    if [ "$venv_owner" != "$svc" ]; then
      finding MEDIUM runtime:python "$svc: .venv owned by $venv_owner, expected $svc"
    fi
  fi
done
