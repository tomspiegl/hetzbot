#!/usr/bin/env bash
# Install the pi.dev coding agent (@mariozechner/pi-coding-agent) globally.
# Depends on Node — calls the node skill's install.sh if needed.
# Idempotent. Runs on the HOST as root.
set -euo pipefail

if command -v pi >/dev/null 2>&1; then
  echo "[pi] already installed: $(pi --version 2>/dev/null || echo unknown)"
  exit 0
fi

# Ensure Node is available (pi is an npm global install).
if ! command -v node >/dev/null 2>&1; then
  if [ -x /opt/hetzbot/skills/runtimes/node/install.sh ]; then
    /opt/hetzbot/skills/runtimes/node/install.sh
  else
    echo "[pi] node not installed and runtime skill missing — install node first" >&2
    exit 1
  fi
fi

# Global install. /etc/npmrc's ignore-scripts=true applies automatically.
npm install -g @mariozechner/pi-coding-agent

command -v pi >/dev/null 2>&1 || {
  echo "[pi] install failed — 'pi' not on PATH" >&2
  exit 1
}

echo "[pi] installed $(pi --version 2>/dev/null || echo ok)"
