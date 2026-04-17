#!/usr/bin/env bash
# Audit restic install + creds. Read-only. Runs on HOST.
# (Snapshot age + retention are reviewed by skills/ops/deploy/review.sh,
# since the timer and orchestration live there.)

set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

# Do we have services? If yes, restic is mandatory.
has_services=0
[ -n "$(find /srv -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" ] && has_services=1

if ! command -v restic >/dev/null 2>&1; then
  if [ "$has_services" = 1 ]; then
    finding CRITICAL restic "not installed but services are deployed (backups would fail)"
  fi
  exit 0
fi

finding OK restic "installed: $(restic version | head -1)"

if [ ! -f /etc/hetzbot/restic.env ]; then
  finding CRITICAL restic "/etc/hetzbot/restic.env missing (cloud-init didn't render?)"
  exit 0
fi

perm=$(stat -c '%a' /etc/hetzbot/restic.env 2>/dev/null || echo "?")
if [ "$perm" != "600" ]; then
  finding HIGH restic "/etc/hetzbot/restic.env perms=$perm (expected 600)"
fi
