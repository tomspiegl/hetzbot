#!/usr/bin/env bash
# Install uv (Astral) host-wide. Runs on the HOST as root. Idempotent.
set -euo pipefail

if command -v uv >/dev/null 2>&1; then
  echo "[python] uv already installed: $(uv --version)"
  exit 0
fi

# The installer drops uv into ~/.local/bin by default.
curl -LsSf https://astral.sh/uv/install.sh | sh

# Move to /usr/local/bin so every service user can run it from PATH.
for bin in uv uvx; do
  if [ -x "/root/.local/bin/$bin" ]; then
    install -m 0755 "/root/.local/bin/$bin" "/usr/local/bin/$bin"
  fi
done

command -v uv >/dev/null 2>&1 || { echo "[python] uv install failed" >&2; exit 1; }

echo "[python] installed $(uv --version) to /usr/local/bin/uv"
