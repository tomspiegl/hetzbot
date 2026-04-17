---
name: hetzbot-review-host
description: Orchestrator. Runs host-level basics + every skill's own review.sh, aggregates findings, prints severity summary. Triggers: user says "review <host>", "audit <host>", "is <host> healthy".
---

# review-host

Runs a read-only audit on one host. Nothing is modified. `review.sh` is
an orchestrator — each skill owns its own review by shipping
`skills/<group>/<skill>/review.sh`. This keeps checks close to the
skill that understands them.

## Usage

```bash
bash $HETZBOT_ROOT/skills/hetzner/review-host/review.sh <host>
# or:
bash skills/hetzner/review-host/review.sh <host>
```

## How it works

1. SSHes to the host (fails CRITICAL if unreachable).
2. Runs `skills/hetzner/review-host/host-basics.sh` for host-level
   concerns (disk, memory, systemd state, patching, firewall, sshd,
   listeners, tailscale).
3. Globs `/opt/hetzbot/skills/*/*/review.sh` and runs each (skipping
   review-host itself).
4. Each script emits findings in a uniform format via the `finding`
   helper in `skills/ops/deploy/lib.sh`:
   ```
   [SEVERITY] category: message
   ```
5. Orchestrator parses + counts + prints summary.

## How to add a review to a skill

Every skill is expected to ship a `review.sh` if it has something
worth checking. Pattern:

```bash
#!/usr/bin/env bash
set -uo pipefail
. /opt/hetzbot/skills/ops/deploy/lib.sh

# Exit early if the skill isn't deployed here.
[ -f /opt/hetzbot/skills/<group>/<skill>/install.sh ] || exit 0

# Emit findings. finding <SEV> <category> <message...>
if condition_that_should_pass; then
  finding OK  "<skill>" "everything fine"
else
  finding HIGH "<skill>" "problem description"
fi
```

Read-only only. A review that mutates the host is no longer a review.

## Severity scale

| Severity | Meaning | Example |
|---|---|---|
| `CRITICAL` | Immediate action; security or availability compromised. | Public SSH open; Postgres down; no restic creds. |
| `HIGH` | Soon. Next business day. | Disk >90%; cert expires <7d; missing runtime. |
| `MEDIUM` | Schedule. Next maintenance window. | Disk 80-90%; pending reboot; patching lag. |
| `LOW` | Informational. Track over time. | Large image cache. |
| `OK` | Reassurance. | Backup ran 14h ago. |

Exit codes: `0` if nothing worse than MEDIUM, `1` on any HIGH, `2` on
any CRITICAL — usable as a cron gate or CI check.

## What currently gets checked

Host-basics (this skill):
- disk `/` and `/var`, memory, systemd state, reboot-required
- unattended-upgrades freshness, needrestart, debsecan
- ufw active + no unexpected Anywhere rules
- sshd hardening (no password auth, no root login, Tailscale-only listen)
- public listeners
- Tailscale online

Per-skill (each skill's own `review.sh`):
- `skills/ops/deploy/review.sh` — systemd units, hardening
  drop-ins, `.env` perms, backup timer, restic snapshot freshness,
  stateful skills without backup hooks.
- `skills/infra/postgres/review.sh` — container health, `pg_isready`,
  per-service DB presence, `127.0.0.1` bind.
- `skills/runtimes/node/review.sh` — Node version (LTS?), `/etc/npmrc`
  lockdown, NodeSource in unattended-upgrades, per-service lockfile.
- `skills/runtimes/python/review.sh` — `uv` present, lockfile hygiene
  (`uv.lock` vs raw `requirements.txt`), venv ownership.

## When to run

- **After `tofu apply`:** confirms cloud-init finished cleanly.
- **After any deploy:** confirms the new service is safe.
- **Before `tofu destroy`:** sanity-check what you're about to remove.
- **Monthly:** operator hygiene routine.
