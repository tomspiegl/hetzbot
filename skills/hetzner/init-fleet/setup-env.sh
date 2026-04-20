#!/usr/bin/env bash
# Populate a fleet's .env: fill OS_ENDPOINT/OS_REGION/OS_BUCKET, create
# the S3 bucket, generate RESTIC_PASSWORD and CONSOLE_ROOT_PASSWORD.
# Secrets are written directly into .env — they never hit stdout.
#
# S3 credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) must be
# created manually in the Hetzner Console under Security → S3 Credentials
# and pasted into .env before running this script.
#
# Runs on the OPERATOR LAPTOP.
# Usage: setup-env.sh <fleet-path> <fleet-name>
#
# Requires: curl, openssl, and S3 credentials already in .env

set -euo pipefail

fleet_path="${1:-}"
fleet_name="${2:-}"

if [ -z "$fleet_path" ] || [ -z "$fleet_name" ]; then
  echo "usage: $0 <fleet-path> <fleet-name>" >&2
  exit 64
fi

env_file="$fleet_path/.env"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file not found — run 'cp .env.example .env' first" >&2
  exit 1
fi

set -a; source "$env_file"; set +a

for cmd in curl openssl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found" >&2; exit 1; }
done

# --- Verify S3 credentials are present ---

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ERROR: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set in .env" >&2
  echo "Generate them in Hetzner Console → Security → S3 Credentials" >&2
  exit 1
fi

echo "S3 credentials found in .env"

# --- Resolve OS_ENDPOINT and OS_REGION ---

region="${OS_REGION:-fsn1}"
endpoint="https://$region.your-objectstorage.com"

sed -i.bak "s|^OS_ENDPOINT=.*|OS_ENDPOINT=$endpoint|" "$env_file"
sed -i.bak "s|^OS_REGION=.*|OS_REGION=$region|" "$env_file"
rm -f "$env_file.bak"

# Reload .env with updated values.
set -a; source "$env_file"; set +a

# --- Create the bucket via S3 API ---

bucket="${fleet_name}-state"
sed -i.bak "s|^OS_BUCKET=.*|OS_BUCKET=$bucket|" "$env_file"
rm -f "$env_file.bak"

echo "creating bucket $bucket in ${region}..."
http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X PUT "https://$bucket.$region.your-objectstorage.com/" \
  -H "Host: $bucket.$region.your-objectstorage.com" \
  --aws-sigv4 "aws:amz:$region:s3" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY")

case "$http_code" in
  200) echo "bucket $bucket created" ;;
  409) echo "bucket $bucket already exists — OK" ;;
  *)   echo "WARNING: bucket creation returned HTTP $http_code — create it manually if needed" ;;
esac

# --- Password policy ---
# RESTIC_PASSWORD: high entropy, never typed manually → 48 hex chars.
# CONSOLE_ROOT_PASSWORD: typed into Hetzner VNC console → 12 alphanumeric
#   chars (no special chars, no ambiguous chars like 0/O, l/1).

generate_console_password() {
  LC_ALL=C tr -dc 'a-hjkmnp-zA-HJKMNP-Z2-9' < /dev/urandom | head -c 12
}

# --- Generate RESTIC_PASSWORD (if not already set) ---

if [ -z "${RESTIC_PASSWORD:-}" ]; then
  restic_pw=$(openssl rand -hex 24)
  sed -i.bak "s|^RESTIC_PASSWORD=.*|RESTIC_PASSWORD=$restic_pw|" "$env_file"
  rm -f "$env_file.bak"
  unset restic_pw
  echo "RESTIC_PASSWORD generated and written to .env"
else
  echo "RESTIC_PASSWORD already set — skipping"
fi

# --- Generate CONSOLE_ROOT_PASSWORD (if not already set) ---

if [ -z "${CONSOLE_ROOT_PASSWORD:-}" ]; then
  console_pw=$(generate_console_password)
  sed -i.bak "s|^CONSOLE_ROOT_PASSWORD=.*|CONSOLE_ROOT_PASSWORD=$console_pw|" "$env_file"
  rm -f "$env_file.bak"
  unset console_pw
  echo "CONSOLE_ROOT_PASSWORD generated and written to .env"
else
  echo "CONSOLE_ROOT_PASSWORD already set — skipping"
fi

echo "done — .env is configured"
