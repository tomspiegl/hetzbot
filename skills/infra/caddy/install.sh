#!/usr/bin/env bash
# Install Caddy from the official cloudsmith apt repo. Idempotent.
# Runs on the HOST as root.
set -euo pipefail

if command -v caddy >/dev/null 2>&1; then
  echo "[caddy] already installed: $(caddy version | head -1)"
  exit 0
fi

install -d -m 0755 /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/caddy.gpg ]; then
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg
  chmod 0644 /etc/apt/keyrings/caddy.gpg
fi

cat > /etc/apt/sources.list.d/caddy.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y caddy

# Cover Caddy with unattended-upgrades.
cat > /etc/apt/apt.conf.d/51unattended-upgrades-caddy <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=cloudsmith,label=Caddy";
};
EOF

echo "[caddy] installed $(caddy version | head -1)"
