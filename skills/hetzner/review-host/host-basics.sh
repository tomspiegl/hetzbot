#!/usr/bin/env bash
# Host-level review: disk, memory, systemd state, patching, firewall,
# sshd, listeners, tailscale. Read-only. Runs on HOST.
# Invoked by the review-host orchestrator alongside each skill's review.sh.

set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

now=$(date +%s)

# --- Disk ---
while read -r fs size used avail pct mount; do
  [ -z "${fs:-}" ] && continue
  pct_num=${pct%\%}
  case "$mount" in
    /|/var)
      if [ "$pct_num" -ge 90 ]; then
        finding HIGH disk "$mount $pct used ($used / $size)"
      elif [ "$pct_num" -ge 80 ]; then
        finding MEDIUM disk "$mount $pct used ($used / $size)"
      else
        finding OK disk "$mount $pct used"
      fi
      ;;
  esac
done < <(df -h / /var 2>/dev/null | tail -n +2)

# --- Memory ---
read -r mem_total mem_used mem_avail < <(free -m 2>/dev/null | awk '/Mem:/ {print $2,$3,$7}')
if [ -n "${mem_total:-}" ]; then
  avail_pct=$(( mem_avail * 100 / mem_total ))
  if [ "$avail_pct" -lt 10 ]; then
    finding HIGH memory "only ${avail_pct}% available (${mem_avail}MB of ${mem_total}MB)"
  elif [ "$avail_pct" -lt 20 ]; then
    finding MEDIUM memory "${avail_pct}% available"
  else
    finding OK memory "${avail_pct}% available"
  fi
fi

# --- systemd state ---
sysstate=$(systemctl is-system-running 2>/dev/null || echo "unknown")
case "$sysstate" in
  running) finding OK systemd "is-system-running=$sysstate" ;;
  degraded)
    failed_list=$(systemctl list-units --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
    finding HIGH systemd "degraded — failed: $failed_list"
    ;;
  *) finding MEDIUM systemd "is-system-running=$sysstate" ;;
esac

# --- Reboot required ---
if [ -f /var/run/reboot-required ]; then
  finding MEDIUM patch "reboot-required flag set"
else
  finding OK patch "no reboot required"
fi

# --- unattended-upgrades last run ---
uu_log=/var/log/unattended-upgrades/unattended-upgrades.log
if [ -f "$uu_log" ]; then
  uu_ts=$(stat -c '%Y' "$uu_log")
  age_h=$(( (now - uu_ts) / 3600 ))
  if [ "$age_h" -gt 72 ]; then
    finding HIGH patch "unattended-upgrades last ran ${age_h}h ago"
  elif [ "$age_h" -gt 48 ]; then
    finding MEDIUM patch "unattended-upgrades last ran ${age_h}h ago"
  else
    finding OK patch "unattended-upgrades ran ${age_h}h ago"
  fi
else
  finding HIGH patch "unattended-upgrades log missing — never run?"
fi

# --- needrestart ---
if command -v needrestart >/dev/null 2>&1; then
  nr_out=$(needrestart -b -r l 2>&1 | grep -E '^NEEDRESTART-' || true)
  nr_kstat=$(grep '^NEEDRESTART-KSTA:' <<<"$nr_out" | awk -F': ' '{print $2}')
  case "${nr_kstat:-0}" in
    ''|0|1) : ;;
    *) finding MEDIUM patch "needrestart: kernel status $nr_kstat (pending reboot)" ;;
  esac
  nr_svc=$(grep -c '^NEEDRESTART-SVC:' <<<"$nr_out" || true)
  if [ "${nr_svc:-0}" -gt 0 ]; then
    finding MEDIUM patch "needrestart: $nr_svc services running old library code"
  fi
fi

# --- debsecan ---
if command -v debsecan >/dev/null 2>&1; then
  debsecan_out=$(debsecan --suite bookworm --format report 2>/dev/null | head -5 || true)
  if grep -qE '\b(High|Critical)\b' <<<"$debsecan_out"; then
    cve_count=$(grep -cE '\b(High|Critical)\b' <<<"$debsecan_out" || true)
    finding HIGH patch "debsecan reports $cve_count High/Critical CVEs"
  fi
fi

# --- ufw ---
ufw_out=$(ufw status verbose 2>/dev/null || echo "UFW_UNAVAILABLE")
if [ "$ufw_out" = "UFW_UNAVAILABLE" ] || ! grep -q 'Status: active' <<<"$ufw_out"; then
  finding CRITICAL firewall "ufw not active"
else
  finding OK firewall "ufw active"
  # Flag unexpected allow-from-Anywhere rules. 443/tcp is allowed on public hosts only.
  while read -r line; do
    [ -z "$line" ] && continue
    if grep -qE 'ALLOW +(IN )?+Anywhere' <<<"$line"; then
      port=$(awk '{print $1}' <<<"$line")
      case "$port" in
        443/tcp|443) : ;;  # expected on public hosts
        *) finding CRITICAL firewall "ufw allows $port from Anywhere (unexpected)" ;;
      esac
    fi
  done < <(grep -E '^[0-9]' <<<"$ufw_out" || true)
fi

# --- sshd ---
if sshd -T 2>/dev/null | grep -qi '^passwordauthentication yes'; then
  finding CRITICAL ssh "sshd accepts password authentication"
else
  finding OK ssh "PasswordAuthentication off"
fi
if sshd -T 2>/dev/null | grep -qi '^permitrootlogin yes'; then
  finding CRITICAL ssh "sshd permits root login"
else
  finding OK ssh "PermitRootLogin off"
fi
if sshd -T 2>/dev/null | grep -qiE '^listenaddress (0\.0\.0\.0|::)'; then
  finding CRITICAL ssh "sshd listens on all interfaces (should be Tailscale only)"
fi

# --- Public listeners ---
while read -r addr; do
  [ -z "$addr" ] && continue
  case "$addr" in
    127.0.0.1:*|'[::1]:'*) : ;;
    100.*|'[fd7a:115c:a1e0:'*) : ;;
    0.0.0.0:443|'[::]:'443) : ;;   # Caddy on public hosts is expected
    0.0.0.0:*|'[::]:'*)
      finding HIGH net "public listener outside expected set: $addr"
      ;;
  esac
done < <(ss -ltnH 2>/dev/null | awk '{print $4}' | sort -u)

# --- Tailscale ---
if ! command -v tailscale >/dev/null 2>&1; then
  finding CRITICAL tailscale "tailscale CLI missing"
else
  ts_json=$(tailscale status --self --json 2>/dev/null || echo "")
  if [ -z "$ts_json" ]; then
    finding HIGH tailscale "tailscale status unavailable"
  else
    online=$(jq -r '.Self.Online // false' <<<"$ts_json" 2>/dev/null)
    if [ "$online" = "true" ]; then
      finding OK tailscale "host online on tailnet"
    else
      finding CRITICAL tailscale "host reports offline from tailnet"
    fi
  fi
fi
