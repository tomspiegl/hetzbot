#!/usr/bin/env bash
# Install a single native service on the host. Runs on HOST as root.
# Called by deploy.sh for each service assigned to the host.
#
# Usage: install-service.sh <name> <source-url>
#
# Source URL format: https://host/path.git[#<sha-or-ref>]

set -euo pipefail

. "$(dirname "$0")/lib.sh"

name="${1:-}"
source_url="${2:-}"
[ -n "$name" ] && [ -n "$source_url" ] || fail "usage: $0 <name> <source-url>"

manifest=/opt/hetzbot/services/$name
[ -d "$manifest" ] || fail "manifest missing: $manifest"

repo_url="${source_url%%#*}"
ref=""
if [[ "$source_url" == *"#"* ]]; then
  ref="${source_url#*#}"
fi

# --- 1. Service user ---
if ! id "$name" >/dev/null 2>&1; then
  log "$name: creating service user"
  useradd --system --home "/srv/$name" --shell /usr/sbin/nologin "$name"
fi
install -d -m 0750 -o "$name" -g "$name" "/srv/$name"

# --- 2. Clone or pull ---
repo_dir="/srv/$name/repo"
if [ ! -d "$repo_dir/.git" ]; then
  log "$name: cloning $repo_url"
  sudo -u "$name" git clone --depth 50 "$repo_url" "$repo_dir"
else
  log "$name: fetching updates"
  sudo -u "$name" git -C "$repo_dir" fetch --all --prune
fi

if [ -n "$ref" ]; then
  log "$name: checking out $ref"
  sudo -u "$name" git -C "$repo_dir" checkout --detach "$ref"
else
  # Default branch HEAD.
  default_branch=$(sudo -u "$name" git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
  sudo -u "$name" git -C "$repo_dir" checkout "$default_branch"
  sudo -u "$name" git -C "$repo_dir" reset --hard "origin/$default_branch"
fi

# --- 3. Lockfile gate ---
check_lockfile "$repo_dir"

# --- 4. Ensure runtime is installed (idempotent per skill) + Build ---
if [ -f "$repo_dir/package-lock.json" ]; then
  /opt/hetzbot/skills/runtimes/node/install.sh
elif [ -f "$repo_dir/uv.lock" ] || [ -f "$repo_dir/pyproject.toml" ]; then
  /opt/hetzbot/skills/runtimes/python/install.sh
fi

if [ -x "$manifest/build.sh" ] || [ -f "$manifest/build.sh" ]; then
  log "$name: running build.sh"
  install -m 0755 "$manifest/build.sh" "/srv/$name/build.sh"
  sudo -u "$name" bash -c "cd '$repo_dir' && bash /srv/$name/build.sh"
else
  # Default builds per lockfile.
  if [ -f "$repo_dir/package-lock.json" ]; then
    log "$name: default Node build (npm ci --ignore-scripts)"
    sudo -u "$name" bash -c "cd '$repo_dir' && npm ci --ignore-scripts"
  elif [ -f "$repo_dir/uv.lock" ]; then
    log "$name: default Python build (uv sync --locked)"
    sudo -u "$name" bash -c "cd '$repo_dir' && uv sync --locked"
  elif [ -f "$repo_dir/go.sum" ]; then
    log "$name: default Go build"
    sudo -u "$name" bash -c "cd '$repo_dir' && go build -trimpath ./..."
  elif [ -f "$repo_dir/Cargo.lock" ]; then
    log "$name: default Rust build"
    sudo -u "$name" bash -c "cd '$repo_dir' && cargo build --release --locked"
  fi
fi

# --- 5. Provision DB + .env on first deploy ---
if [ ! -f "/srv/$name/.env" ]; then
  if [ -x "$manifest/provision.sh" ]; then
    log "$name: running custom provision.sh"
    bash "$manifest/provision.sh"
  else
    log "$name: default provision (Postgres DB + .env)"
    /opt/hetzbot/skills/infra/postgres/install.sh "$name"
  fi
fi

# --- 6. Install systemd unit + hardening drop-in ---
unit_src="$manifest/$name.service"
[ -f "$unit_src" ] || fail "$unit_src missing"
install -m 0644 "$unit_src" "/etc/systemd/system/$name.service"

timer_src="$manifest/$name.timer"
if [ -f "$timer_src" ]; then
  install -m 0644 "$timer_src" "/etc/systemd/system/$name.timer"
fi

hardening_dir="/etc/systemd/system/$name.service.d"
install -d -m 0755 "$hardening_dir"
cat > "$hardening_dir/90-hardening.conf" <<HARDEN
[Service]
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/srv/$name
ProtectHome=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native
HARDEN

for extra in "$manifest"/*.conf; do
  [ -f "$extra" ] || continue
  install -m 0644 "$extra" "$hardening_dir/$(basename "$extra")"
  log "$name: installed drop-in $(basename "$extra")"
done

# --- 7. Enable + start ---
systemctl daemon-reload
if [ -f "$timer_src" ]; then
  systemctl enable --now "$name.timer"
else
  systemctl enable --now "$name.service"
fi

log "$name: installed"
