#!/usr/bin/env bash
# Backup orchestrator. Runs on the HOST under hetzbot-backup.timer.
# Reads restic creds from /etc/hetzbot/restic.env (systemd EnvironmentFile).
#
# Delegates skill-specific backup steps (e.g. pg_dump) to
# /opt/hetzbot/skills/infra/*/backup.sh. Then runs a single restic
# pass over the well-known backup paths.

set -euo pipefail

. "$(dirname "$0")/lib.sh"

: "${RESTIC_REPOSITORY:?missing — /etc/hetzbot/restic.env not loaded?}"
: "${RESTIC_PASSWORD:?missing}"

# --- 1. Per-skill pre-backup hooks ---
for hook in /opt/hetzbot/skills/infra/*/backup.sh; do
  [ -x "$hook" ] || continue
  name=$(basename "$(dirname "$hook")")
  [ "$name" = "deploy" ] && continue   # skip self
  log "skill:$name — running backup hook"
  "$hook"
done

# --- 2. restic repo ---
log "restic init (no-op if already initialized)"
restic snapshots >/dev/null 2>&1 || restic init

log "restic backup"
restic backup \
  --tag hetzbot \
  --exclude /srv/*/repo/node_modules \
  --exclude /srv/*/repo/target \
  --exclude /srv/*/repo/.venv \
  /srv \
  /var/lib/docker/volumes \
  /var/lib/caddy \
  /var/backups \
  /var/log/archive \
  /etc

log "restic forget + prune"
restic forget --prune \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12

log "done"
