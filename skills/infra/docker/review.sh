#!/usr/bin/env bash
# Audit docker daemon + hardening. Read-only. Runs on HOST.
set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

if ! command -v docker >/dev/null 2>&1; then
  # Only flag if any compose skill is installed.
  for compose in /opt/hetzbot/skills/infra/*/docker-compose.yml; do
    [ -f "$compose" ] && { finding CRITICAL docker "compose skills installed but docker binary missing"; exit 0; }
  done
  exit 0
fi

active=$(systemctl is-active docker 2>/dev/null || echo unknown)
case "$active" in
  active) finding OK docker "daemon active" ;;
  *)      finding CRITICAL docker "daemon state=$active" ;;
esac

config=/etc/docker/daemon.json
if [ ! -f "$config" ]; then
  finding HIGH docker "daemon.json missing (hardening not applied)"
else
  for key in '"no-new-privileges": true' '"log-driver": "journald"' '"live-restore": true' '"userland-proxy": false'; do
    grep -q "$key" "$config" \
      && finding OK docker "daemon.json: ${key%:*}" \
      || finding HIGH docker "daemon.json missing: $key"
  done
fi
