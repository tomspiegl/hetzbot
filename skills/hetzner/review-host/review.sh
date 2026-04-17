#!/usr/bin/env bash
# Review orchestrator. Runs on OPERATOR LAPTOP; SSHes once, runs
# host-basics.sh + every skill's review.sh, aggregates findings,
# prints a severity summary.
#
# Usage: review.sh <host>
#
# Exit codes:
#   0 — no findings worse than MEDIUM
#   1 — at least one HIGH finding
#   2 — at least one CRITICAL finding
#
# Convention each skill must satisfy:
#   skills/<group>/<skill>/review.sh prints lines in the form
#     [SEVERITY] category:  message
#   where SEVERITY ∈ {CRITICAL HIGH MEDIUM LOW OK}.
#   The helper `finding` in skills/ops/deploy/lib.sh emits this.

set -uo pipefail

host="${1:-}"
[ -n "$host" ] || { echo "usage: $0 <host>" >&2; exit 64; }

declare -A counts=( [CRITICAL]=0 [HIGH]=0 [MEDIUM]=0 [LOW]=0 [OK]=0 )
worst=OK

emit() {
  printf '%s\n' "$1"
  if [[ "$1" =~ ^\[([A-Z]+)[[:space:]]*\] ]]; then
    local sev="${BASH_REMATCH[1]}"
    [[ -n "${counts[$sev]+set}" ]] || return
    counts[$sev]=$(( counts[$sev] + 1 ))
    case "$sev" in
      CRITICAL) worst=CRITICAL ;;
      HIGH)     [ "$worst" != CRITICAL ] && worst=HIGH ;;
      MEDIUM)   { [ "$worst" = OK ] || [ "$worst" = LOW ]; } && worst=MEDIUM ;;
      LOW)      [ "$worst" = OK ] && worst=LOW ;;
    esac
  fi
}

# --- Reachability (laptop-side) ---
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" true 2>/dev/null; then
  emit "[CRITICAL] host:           unreachable over Tailscale"
  printf '\n--- Summary ---\n  CRITICAL:  1\n  worst:     CRITICAL\n'
  exit 2
fi

# --- Run host-basics + every skill's review.sh in one SSH session ---
remote=$(ssh "$host" 'bash -s' <<'ORCHESTRATE'
set -uo pipefail

# 1. Host-level basics
if [ -x /opt/hetzbot/skills/hetzner/review-host/host-basics.sh ]; then
  /opt/hetzbot/skills/hetzner/review-host/host-basics.sh
fi

# 2. Every skill's review.sh (skip review-host itself)
for review in /opt/hetzbot/skills/*/*/review.sh; do
  [ -x "$review" ] || continue
  name=$(basename "$(dirname "$review")")
  [ "$name" = "review-host" ] && continue
  "$review" 2>&1 || echo "[HIGH    ] $name: review.sh crashed"
done
ORCHESTRATE
) || true

while IFS= read -r line; do
  [ -z "$line" ] && continue
  emit "$line"
done <<<"$remote"

# --- Summary ---
total=$(( counts[CRITICAL] + counts[HIGH] + counts[MEDIUM] + counts[LOW] + counts[OK] ))
printf '\n--- Summary ---\n'
for k in CRITICAL HIGH MEDIUM LOW OK; do
  printf '  %-10s %d\n' "$k:" "${counts[$k]}"
done
printf '  %-10s %d\n' "Total:" "$total"
printf '  worst:     %s\n' "$worst"

case "$worst" in
  CRITICAL) exit 2 ;;
  HIGH)     exit 1 ;;
  *)        exit 0 ;;
esac
