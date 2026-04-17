#!/usr/bin/env bash
# Install Node.js LTS with hardened npm defaults.
# Runs on the HOST as root. Idempotent.
set -euo pipefail

NODE_MAJOR=20

if command -v node >/dev/null 2>&1; then
  current=$(node --version)
  case "$current" in
    v"$NODE_MAJOR".*) echo "[node] already at $current — ok"; exit 0 ;;
    *) echo "[node] found $current, expected v${NODE_MAJOR}.x — proceeding to install";;
  esac
fi

install -d -m 0755 /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  chmod 0644 /etc/apt/keyrings/nodesource.gpg
fi

cat > /etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main
EOF

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

# Host-wide npm safety defaults.
cat > /etc/npmrc <<'EOF'
ignore-scripts=true
fund=false
audit-level=high
EOF
chmod 0644 /etc/npmrc

# unattended-upgrades covers NodeSource.
cat > /etc/apt/apt.conf.d/51unattended-upgrades-nodesource <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Node Source";
    "origin=deb.nodesource.com";
};
EOF

echo "[node] installed $(node --version) with /etc/npmrc lockdown"
