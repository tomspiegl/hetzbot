#!/usr/bin/env bash
# Audit Caddy install, cert validity per vhost, no port-80 listener.
# Read-only. Runs on HOST. Silent exit if caddy isn't expected here.

set -uo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

# If caddy isn't installed, report OK only if host is headless.
# (Which is which is determined by 'is there a /etc/caddy/Caddyfile?'.)
if ! command -v caddy >/dev/null 2>&1; then
  [ -f /etc/caddy/Caddyfile ] && finding CRITICAL caddy "Caddyfile present but caddy binary missing"
  exit 0
fi

# --- Active? ---
active=$(systemctl is-active caddy 2>/dev/null || echo unknown)
case "$active" in
  active)   finding OK caddy "unit active" ;;
  inactive) finding CRITICAL caddy "unit inactive (public host should have caddy running)" ;;
  *)        finding HIGH caddy "unit state=$active" ;;
esac

# --- Port 80 must never be open ---
if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(:80$|:80 )'; then
  finding CRITICAL caddy "port 80 listener detected (hetzbot is HTTPS-only)"
fi

# --- Cert expiry per vhost ---
now=$(date +%s)
if [ -f /etc/caddy/Caddyfile ]; then
  mapfile -t vhosts < <(awk '/^[a-zA-Z0-9][a-zA-Z0-9.-]+ +\{/ {print $1}' /etc/caddy/Caddyfile)
  for vh in "${vhosts[@]}"; do
    case "$vh" in
      \(*) continue ;;  # snippet label, skip
    esac
    expiry=$(echo | timeout 5 openssl s_client -servername "$vh" -connect "$vh:443" 2>/dev/null \
             | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiry" ]; then
      finding MEDIUM caddy "$vh: cert not reachable (not yet issued?)"
      continue
    fi
    exp_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    days_left=$(( (exp_epoch - now) / 86400 ))
    if [ "$days_left" -lt 7 ]; then
      finding HIGH caddy "$vh: cert expires in ${days_left}d"
    elif [ "$days_left" -lt 14 ]; then
      finding MEDIUM caddy "$vh: cert expires in ${days_left}d"
    else
      finding OK caddy "$vh: cert valid for ${days_left}d"
    fi
  done
fi
