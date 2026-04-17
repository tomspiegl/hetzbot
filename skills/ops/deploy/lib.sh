#!/usr/bin/env bash
# Shared helpers for hetzbot host-side scripts.
# Sourced via /opt/hetzbot/skills/ops/deploy/lib.sh by sibling
# scripts and by sibling skills under /opt/hetzbot/skills/infra/*/.

set -euo pipefail

log()  { printf '[hetzbot] %s\n' "$*" >&2; }
fail() { printf '[hetzbot] ERROR: %s\n' "$*" >&2; exit 1; }

# check_lockfile <service_dir>
# Refuses to deploy a service without a pinned dependency manifest.
check_lockfile() {
  local dir="$1"
  [ -d "$dir" ] || fail "service dir missing: $dir"
  if   [ -f "$dir/package.json" ] && [ ! -f "$dir/package-lock.json" ]; then
    fail "$dir: package.json without package-lock.json (lockfile required)"
  elif [ -f "$dir/pyproject.toml" ] && [ ! -f "$dir/uv.lock" ]; then
    fail "$dir: pyproject.toml without uv.lock (lockfile required)"
  elif [ -f "$dir/go.mod" ] && [ ! -f "$dir/go.sum" ]; then
    fail "$dir: go.mod without go.sum (lockfile required)"
  elif [ -f "$dir/Cargo.toml" ] && [ ! -f "$dir/Cargo.lock" ]; then
    fail "$dir: Cargo.toml without Cargo.lock (lockfile required)"
  fi
}

# generate_password — 32 hex chars from openssl.
generate_password() {
  openssl rand -hex 32
}

# write_env_file <path> <key=value>...
# Mode 0640, owner root:<service_user> (caller sets service_user via env).
write_env_file() {
  local path="$1"; shift
  umask 027
  printf '%s\n' "$@" > "$path"
  chmod 0640 "$path"
}

# finding <severity> <category> <message...>
# Used by every skill's review.sh. Orchestrator (review-host) aggregates
# stdout and counts severities. Valid severities: CRITICAL HIGH MEDIUM LOW OK.
finding() {
  local sev=$1 cat=$2
  shift 2
  printf '[%-8s] %-14s %s\n' "$sev" "$cat:" "$*"
}
