#!/usr/bin/env bash
# Assemble /etc/caddy/Caddyfile from per-service snippets + validate + reload.
# Runs on HOST (public = true hosts only).

set -euo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

caddyfile=/etc/caddy/Caddyfile
tmp=$(mktemp)

cat > "$tmp" <<'GLOBAL'
{
    auto_https disable_redirects
    servers {
        trusted_proxies static private_ranges
    }
}

(header_defaults) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }
}

GLOBAL

for snippet in /opt/hetzbot/services/*/caddy.conf; do
  [ -f "$snippet" ] || continue
  name=$(basename "$(dirname "$snippet")")
  {
    echo "# --- $name ---"
    cat "$snippet"
    echo
  } >> "$tmp"
done

log "validating assembled Caddyfile"
caddy validate --config "$tmp" --adapter caddyfile

install -m 0644 "$tmp" "$caddyfile"
rm -f "$tmp"

log "reloading caddy"
systemctl reload caddy
