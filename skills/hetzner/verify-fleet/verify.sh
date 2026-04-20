#!/usr/bin/env bash
# Host-side verification: tests that each subsystem actually works
# end-to-end (not just that config files exist).
# Runs on HOST. Uses the standard finding() helper.
#
# Usage: verify.sh
#   Runs all checks on the current host and emits findings.

set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

now=$(date +%s)

# --- Restic: can we actually list snapshots? ---
if [ -f /etc/hetzbot/restic.env ] && command -v restic >/dev/null 2>&1; then
  set -a; . /etc/hetzbot/restic.env; set +a
  snap_json=$(restic snapshots --latest 1 --json 2>/dev/null || echo "[]")
  snap_time=$(echo "$snap_json" | jq -r '.[0].time // "none"' 2>/dev/null || echo "err")
  case "$snap_time" in
    none)
      finding HIGH verify:backup "restic repo has 0 snapshots"
      ;;
    err)
      finding HIGH verify:backup "restic snapshots query failed"
      ;;
    *)
      snap_epoch=$(date -d "$snap_time" +%s 2>/dev/null || echo 0)
      age_h=$(( (now - snap_epoch) / 3600 ))
      if [ "$age_h" -gt 48 ]; then
        finding HIGH verify:backup "last snapshot ${age_h}h ago"
      else
        finding OK verify:backup "last snapshot ${age_h}h ago"
      fi
      ;;
  esac
else
  finding HIGH verify:backup "restic not available or env missing"
fi

# --- Postgres: can we connect and list DBs? ---
if command -v pg_isready >/dev/null 2>&1; then
  if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    pg_pass=""
    [ -f /etc/hetzbot/postgres_superuser ] && pg_pass=$(cat /etc/hetzbot/postgres_superuser)
    db_count=$(PGPASSWORD="$pg_pass" psql -h 127.0.0.1 -U postgres -Atc "SELECT count(*) FROM pg_database WHERE datistemplate = false AND datname != 'postgres'" 2>/dev/null || echo "err")
    if [ "$db_count" != "err" ] && [ "$db_count" -gt 0 ] 2>/dev/null; then
      finding OK verify:postgres "$db_count user database(s)"
    elif [ "$db_count" = "0" ]; then
      finding MEDIUM verify:postgres "no user databases found"
    else
      finding HIGH verify:postgres "could not query pg_database"
    fi

    # Check pg_dump files exist for each service DB
    dbs=$(PGPASSWORD="$pg_pass" psql -h 127.0.0.1 -U postgres -Atc "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres'" 2>/dev/null || true)
    for db in $dbs; do
      today=$(date +%Y-%m-%d)
      dump="/var/backups/pg/${db}-${today}.dump"
      if [ -s "$dump" ]; then
        dump_size=$(du -h "$dump" | cut -f1)
        finding OK "verify:pg_dump:$db" "today's dump exists ($dump_size)"
      else
        finding HIGH "verify:pg_dump:$db" "no dump for today — backup may not have run"
      fi
    done
  else
    finding HIGH verify:postgres "pg_isready failed on 127.0.0.1:5432"
  fi
fi

# --- Service timers fire correctly ---
for svc_dir in /srv/*/; do
  [ -d "$svc_dir" ] || continue
  svc=$(basename "$svc_dir")

  if systemctl is-enabled "${svc}.timer" >/dev/null 2>&1; then
    next=$(systemctl show "${svc}.timer" --property=NextElapseUSecRealtime --value 2>/dev/null)
    if [ -n "$next" ] && [ "$next" != "n/a" ]; then
      finding OK "verify:timer:$svc" "next run: $next"
    else
      finding MEDIUM "verify:timer:$svc" "timer enabled but no next-run scheduled"
    fi
  fi
done

# --- Google API: token refreshable? ---
if [ -f /etc/hetzbot/google/google-token.json ]; then
  google_ok=$(python3 -c "
import json
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
with open('/etc/hetzbot/google/google-token.json') as f:
    t = json.load(f)
c = Credentials(token=t.get('token'), refresh_token=t['refresh_token'],
    token_uri=t['token_uri'], client_id=t['client_id'],
    client_secret=t['client_secret'], scopes=t.get('scopes', []))
if not c.valid:
    c.refresh(Request())
print('ok')
" 2>&1 || echo "err")
  if [ "$google_ok" = "ok" ]; then
    finding OK verify:google "token valid / refreshable"
  else
    finding HIGH verify:google "token refresh failed: ${google_ok:0:80}"
  fi
fi

# --- Disk pressure ---
disk_pct=$(df / --output=pcent | tail -1 | tr -d ' %')
if [ "$disk_pct" -ge 90 ] 2>/dev/null; then
  finding HIGH verify:disk "root filesystem ${disk_pct}% full"
elif [ "$disk_pct" -ge 80 ] 2>/dev/null; then
  finding MEDIUM verify:disk "root filesystem ${disk_pct}% full"
else
  finding OK verify:disk "root filesystem ${disk_pct}% used"
fi
