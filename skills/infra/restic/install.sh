#!/usr/bin/env bash
# Install restic from Debian apt. Idempotent.
# Runs on the HOST as root.
set -euo pipefail

if command -v restic >/dev/null 2>&1; then
  echo "[restic] already installed: $(restic version | head -1)"
  exit 0
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y restic
echo "[restic] installed $(restic version | head -1)"
