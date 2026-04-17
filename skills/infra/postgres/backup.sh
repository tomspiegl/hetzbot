#!/usr/bin/env bash
# Postgres backup hook — one pg_dump -Fc per service database.
# Invoked by /opt/hetzbot/skills/ops/deploy/backup-now.sh. Dumps land under
# /var/backups/pg/ and are picked up by the subsequent restic pass.

set -euo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

pgdir=/var/backups/pg
install -d -m 0750 "$pgdir"

mapfile -t dbs < <(docker exec postgres psql -U postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1')")

for db in "${dbs[@]}"; do
  [ -n "$db" ] || continue
  out="$pgdir/${db}-$(date +%F).dump"
  log "postgres:$db → $out"
  docker exec postgres pg_dump -U postgres -Fc "$db" > "$out"
done

# Keep 14 days of dumps on host; restic retention owns the long tail.
find "$pgdir" -type f -name '*.dump' -mtime +14 -delete
