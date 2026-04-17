#!/usr/bin/env bash
# Quick cross-host status summary. For the operator's `just status`.
# Intentionally minimal — use the check-fleet SKILL.md for a deep audit.
#
# Reads the host list from `tofu output -json hosts` and, for each,
# prints uptime + the running systemd services that match either
# "postgres" or one of the service names under /opt/hetzbot/services.
#
# Runs locally; SSHes into each host over the tailnet.

set -euo pipefail

cd "${HETZBOT_FLEET_ROOT:-$PWD}"

hosts=$(tofu -chdir=tofu output -json hosts | jq -r 'keys[]')

for host in $hosts; do
  echo "=== $host ==="
  ssh "$host" '
    uptime
    pattern="postgres"
    if [ -d /opt/hetzbot/services ]; then
      svcs=$(ls /opt/hetzbot/services 2>/dev/null | tr "\n" "|" | sed "s/|$//")
      [ -n "$svcs" ] && pattern="postgres|$svcs"
    fi
    systemctl list-units --type=service --state=running \
      | grep -E "$pattern" || true
  '
done
