#!/usr/bin/env bash
# Worklog helper — manages .work/{fleet}/ state in the hetzbot repo.
# Sourced by skills that need to read/write fleet config or append log entries.
#
# Files per fleet:
#   .work/{fleet}/conf.json  — fleet metadata (see worklog-schema.json)
#   .work/{fleet}/work.log   — append-only timestamped operation log
#
# Usage:
#   source $HETZBOT_ROOT/skills/worklog.sh
#   worklog_init  <fleet-name> <fleet-path>   # create conf.json + first log entry
#   worklog_entry <fleet-name> <message>       # append a timestamped log line
#   worklog_conf  <fleet-name>                 # print conf.json path (for jq reads)
#   worklog_fleet_names                        # list known fleet names

set -euo pipefail

HETZBOT_ROOT="${HETZBOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORK_DIR="$HETZBOT_ROOT/.work"
WORKLOG_TEMPLATE="$HETZBOT_ROOT/skills/worklog-template.json"

worklog_init() {
  local name="$1" fleet_path="$2"
  local dir="$WORK_DIR/$name"
  mkdir -p "$dir"

  local abs_path
  abs_path=$(cd "$fleet_path" && pwd)

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  sed -e "s|{{FLEET_NAME}}|$name|g" \
      -e "s|{{FLEET_PATH}}|$abs_path|g" \
      -e "s|{{CREATED}}|$ts|g" \
      "$WORKLOG_TEMPLATE" > "$dir/conf.json"

  worklog_entry "$name" "init-fleet: scaffolded at $abs_path"
}

worklog_entry() {
  local name="$1" msg="$2"
  local dir="$WORK_DIR/$name"
  mkdir -p "$dir"
  printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$dir/work.log"
}

worklog_conf() {
  local name="$1"
  echo "$WORK_DIR/$name/conf.json"
}

worklog_fleet_names() {
  if [ -d "$WORK_DIR" ]; then
    for d in "$WORK_DIR"/*/conf.json; do
      [ -f "$d" ] && basename "$(dirname "$d")"
    done
  fi
}
