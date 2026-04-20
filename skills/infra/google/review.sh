#!/usr/bin/env bash
# Review Google API credentials on a host.
# Emits findings via the standard finding() helper.

set -euo pipefail

. /opt/hetzbot/skills/ops/deploy/lib.sh

creds="/etc/hetzbot/google/google-credentials.json"
token="/etc/hetzbot/google/google-token.json"

if [ ! -f "$creds" ]; then
    finding HIGH google "credentials file missing: $creds"
elif [ "$(stat -c '%a' "$creds" 2>/dev/null || stat -f '%Lp' "$creds")" != "600" ]; then
    finding HIGH google "credentials file permissions not 0600"
fi

if [ ! -f "$token" ]; then
    finding HIGH google "token file missing: $token"
elif [ "$(stat -c '%a' "$token" 2>/dev/null || stat -f '%Lp' "$token")" != "600" ]; then
    finding HIGH google "token file permissions not 0600"
fi
