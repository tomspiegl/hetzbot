#!/usr/bin/env bash
# Install Docker Engine + Compose plugin from docker.com. Idempotent.
# Runs on the HOST as root.
set -euo pipefail

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "[docker] already installed: $(docker --version)"
  # Re-apply daemon.json in case it drifted.
else
  install -d -m 0755 /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod 0644 /etc/apt/keyrings/docker.gpg
  fi

  arch=$(dpkg --print-architecture)
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $codename stable
EOF

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
fi

# Hardened daemon config (written every time; reload if it changed).
install -d -m 0755 /etc/docker
tmp=$(mktemp)
cat > "$tmp" <<'EOF'
{
  "log-driver": "journald",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true
}
EOF
if ! cmp -s "$tmp" /etc/docker/daemon.json 2>/dev/null; then
  install -m 0644 "$tmp" /etc/docker/daemon.json
  systemctl reload-or-restart docker
fi
rm -f "$tmp"

# unattended-upgrades covers docker.com.
cat > /etc/apt/apt.conf.d/51unattended-upgrades-docker <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=download.docker.com";
};
EOF

echo "[docker] ready — $(docker --version)"
