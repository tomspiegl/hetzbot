#!/usr/bin/env bash
# Audit deploy outputs: systemd units, hardening drop-ins, env perms,
# backup timer, restic snapshot freshness. Read-only. Runs on HOST.
set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

now=$(date +%s)

# --- Enumerate deployed services (by /srv/<svc>/) ---
mapfile -t services < <(find /srv -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)

if [ ${#services[@]} -eq 0 ]; then
  finding OK deploy:svc "no services deployed"
else
  for svc in "${services[@]}"; do
    active=$(systemctl is-active "$svc" 2>/dev/null || true)
    nrestarts=$(systemctl show "$svc" --property=NRestarts --value 2>/dev/null || echo 0)

    case "$active" in
      active)   finding OK "deploy:$svc" "unit active" ;;
      inactive) finding HIGH "deploy:$svc" "unit inactive" ;;
      failed)   finding HIGH "deploy:$svc" "unit failed" ;;
      *)        finding MEDIUM "deploy:$svc" "unit state=$active" ;;
    esac

    if [ "${nrestarts:-0}" -gt 10 ]; then
      finding HIGH "deploy:$svc" "restarted $nrestarts times since boot"
    elif [ "${nrestarts:-0}" -gt 3 ]; then
      finding MEDIUM "deploy:$svc" "restarted $nrestarts times since boot"
    fi

    if [ -f "/etc/systemd/system/$svc.service.d/90-hardening.conf" ]; then
      finding OK "deploy:$svc" "hardening drop-in present"
    else
      finding HIGH "deploy:$svc" "missing 90-hardening.conf drop-in"
    fi

    if [ -f "/srv/$svc/.env" ]; then
      perm=$(stat -c '%a %U:%G' "/srv/$svc/.env" 2>/dev/null || echo "?")
      if [ "$perm" = "640 root:$svc" ]; then
        finding OK "deploy:$svc" ".env perms correct ($perm)"
      else
        finding HIGH "deploy:$svc" ".env perms wrong: $perm (expected 640 root:$svc)"
      fi
    else
      finding HIGH "deploy:$svc" ".env missing at /srv/$svc/.env"
    fi

    errlog=$(journalctl -u "$svc" -n 100 --no-pager 2>/dev/null \
             | grep -ciE 'error|panic|fatal|unhandled' || true)
    if [ "${errlog:-0}" -gt 10 ]; then
      finding MEDIUM "deploy:$svc" "$errlog error/panic/fatal lines in last 100 journal entries"
    fi
  done
fi

# --- Backup timer ---
timer_state=$(systemctl is-enabled hetzbot-backup.timer 2>/dev/null || echo disabled)
if [ "$timer_state" = "enabled" ]; then
  finding OK deploy:backup "hetzbot-backup.timer enabled"
else
  finding CRITICAL deploy:backup "hetzbot-backup.timer is $timer_state"
fi

# --- Per-skill backup hooks exist if skill is stateful ---
for compose in /opt/hetzbot/skills/*/*/docker-compose.yml; do
  [ -f "$compose" ] || continue
  skill_dir=$(dirname "$compose")
  name=$(basename "$skill_dir")
  if [ -x "$skill_dir/backup.sh" ]; then
    finding OK "deploy:backup" "$name has backup.sh hook"
  else
    finding HIGH "deploy:backup" "$name is stateful (has docker-compose.yml) but no backup.sh hook"
  fi
done

# --- Restic repo reachable + snapshot age ---
if [ ! -f /etc/hetzbot/restic.env ]; then
  finding CRITICAL deploy:backup "/etc/hetzbot/restic.env missing"
elif ! command -v restic >/dev/null 2>&1; then
  finding CRITICAL deploy:backup "restic binary not installed"
else
  set -a; . /etc/hetzbot/restic.env; set +a
  snap_time=$(restic snapshots --last 1 --json 2>/dev/null | jq -r '.[0].time // "none"' 2>/dev/null || echo err)
  case "$snap_time" in
    none) finding HIGH deploy:backup "restic repo has no snapshots yet" ;;
    err)  finding HIGH deploy:backup "restic snapshots query failed" ;;
    *)
      snap_epoch=$(date -d "$snap_time" +%s 2>/dev/null || echo 0)
      age_h=$(( (now - snap_epoch) / 3600 ))
      if [ "$age_h" -gt 72 ]; then
        finding HIGH deploy:backup "last restic snapshot ${age_h}h ago"
      elif [ "$age_h" -gt 48 ]; then
        finding MEDIUM deploy:backup "last restic snapshot ${age_h}h ago"
      else
        finding OK deploy:backup "last restic snapshot ${age_h}h ago"
      fi
      ;;
  esac

  # Freshness of on-host pg_dump files (per-skill backup output).
  fresh_dumps=$(find /var/backups/pg -type f -name '*.dump' -mtime -2 2>/dev/null | wc -l | tr -d ' ')
  if [ ${#services[@]} -gt 0 ] && [ "$fresh_dumps" -eq 0 ]; then
    finding HIGH deploy:backup "no pg_dump files younger than 48h"
  elif [ "$fresh_dumps" -gt 0 ]; then
    finding OK deploy:backup "$fresh_dumps pg_dump file(s) younger than 48h"
  fi
fi
