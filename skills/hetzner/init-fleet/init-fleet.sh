#!/usr/bin/env bash
# Scaffold a new fleet repo from the template in this skill dir.
# Runs on the OPERATOR LAPTOP.
#
# Usage: init-fleet.sh <target-path> <fleet-name>

set -euo pipefail

target="${1:-}"
name="${2:-}"

if [ -z "$target" ] || [ -z "$name" ]; then
  echo "usage: $0 <target-path> <fleet-name>" >&2
  exit 64
fi

if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null || true)" ]; then
  # Resumable: if the dir already looks like a scaffolded fleet, skip the
  # copy and let the caller continue with downstream steps (git init, etc.).
  if [ -f "$target/hosts.tfvars" ] && [ -f "$target/.env.example" ]; then
    echo "already scaffolded: $target (hosts.tfvars + .env.example present) — skipping copy"
    exit 0
  fi
  echo "ERROR: $target exists, is not empty, and doesn't look like a scaffolded fleet" >&2
  exit 1
fi

src="$(cd "$(dirname "$0")/template" && pwd)"
[ -d "$src" ] || { echo "template dir missing: $src" >&2; exit 2; }

mkdir -p "$target"
cp -a "$src"/. "$target"/

# Substitute placeholders.
find "$target" -type f \( -name '*.md' -o -name '*.example' -o -name '*.tf' -o -name 'justfile' -o -name 'hosts.tfvars' \) -print0 \
  | xargs -0 -I{} sed -i.bak -e "s|{{FLEET_NAME}}|$name|g" {}
find "$target" -type f -name '*.bak' -delete

echo "scaffolded $name at $target"
echo ""
echo "next:"
echo "  cd $target"
echo "  cp .env.example .env   # fill from your personal vault"
echo "  just init              # one-time tofu backend init"
