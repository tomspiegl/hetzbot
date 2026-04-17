#!/usr/bin/env bash
# Audit pi.dev coding agent install. Optional infra — silent if absent.
set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

if ! command -v pi >/dev/null 2>&1; then
  # Optional — absence is not a finding.
  exit 0
fi

pi_v=$(pi --version 2>/dev/null | head -1 || echo "?")
finding OK pi "installed: $pi_v"

# Verify it's the expected package (not some other `pi` binary on PATH).
if ! pi --help 2>&1 | grep -qi 'coding-agent\|mariozechner\|pi.dev' ; then
  finding MEDIUM pi "'pi' on PATH is not the pi.dev coding agent (another binary?)"
fi

# /etc/hetzbot/pi.env presence + perms — but never read the content.
if [ -f /etc/hetzbot/pi.env ]; then
  perm=$(stat -c '%a %U:%G' /etc/hetzbot/pi.env 2>/dev/null || echo "?")
  if [ "$perm" = "600 root:root" ]; then
    finding OK pi "/etc/hetzbot/pi.env perms correct ($perm)"
  else
    finding HIGH pi "/etc/hetzbot/pi.env perms=$perm (expected 600 root:root)"
  fi
else
  finding MEDIUM pi "/etc/hetzbot/pi.env missing — pi has no credentials configured"
fi
