---
name: hetzbot-backup
description: Force a backup run on a host now, out-of-band from the systemd timer. Triggers: user says "backup <host>", "force a backup", "snapshot the data", or anything before a risky change. Runs per-skill pre-backup hooks (pg_dump, etc.) then a single restic pass. Verifies a new snapshot landed.
---

# backup

Invokes the same backup pipeline that `hetzbot-backup.timer` runs
nightly, but on demand. Safe to run anytime — the job is idempotent
and restic handles concurrent snapshots.

Typical reasons to run this skill:

- Before `tofu destroy`, `remove-service`, or any "dangerous edit".
- After a manually-applied data fix, so the new state is captured
  before the next risky operation.
- To verify the backup pipeline works end-to-end (new snapshot +
  forget/prune) without waiting for the timer.

Underlying mechanism: `skills/ops/deploy/backup-now.sh` on the host.
Discovers `skills/infra/*/backup.sh` hooks (currently only
`postgres/backup.sh` → `pg_dump -Fc`), then `restic backup` over
`/srv`, docker volumes, `/var/lib/caddy`, `/var/backups`,
`/var/log/archive`, `/etc`. Finishes with
`restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 12`.

## Program

```python
# 1. Identify.

host_name = ask("Host to back up?", choices=list(hosts_tfvars.keys()))

# 2. Capture baseline — snapshot count before.

result = run(f"ssh {host_name} sudo restic snapshots --json 2>/dev/null | jq 'length'")
if result.exit_code != 0:
    fail(
        "can't query restic — is the host reachable and restic installed? "
        f"Try: ssh {host_name} sudo /opt/hetzbot/skills/infra/restic/review.sh"
    )
before = int(result.stdout.strip())

# 3. Inform (backups can be slow on fat hosts).

inform(f"""Forcing backup on {host_name}.
  - pg_dump per database → /var/backups/pg/
  - restic backup → (configured repo)
  - restic forget/prune (keep 7d/4w/12m)
Typical wall time: 30s – a few minutes depending on delta size.
Output streams from the host.""")

# 4. Run.

if run(f"ssh {host_name} sudo /opt/hetzbot/skills/ops/deploy/backup-now.sh").exit_code != 0:
    fail(
        "backup-now.sh failed — see Recovery below. Do NOT retry "
        "blindly; the first failure may have left a partial pg_dump "
        "or a restic lock that needs inspecting."
    )

# 5. Verify — a new snapshot appeared.

after = int(run(f"ssh {host_name} sudo restic snapshots --json 2>/dev/null | jq 'length'").stdout.strip())
if after <= before:
    warn(
        f"snapshot count unchanged ({before} → {after}) — restic may "
        "have deduplicated to nothing, but more likely something "
        "went wrong. Inspect:\n"
        f"  ssh {host_name} sudo restic snapshots | tail -5"
    )
    fail()

latest = run(f"ssh {host_name} sudo restic snapshots --last 1 --json | jq -r '.[0].time'").stdout.strip()
inform(f"Backup on {host_name} complete. Snapshots: {before} → {after}. Latest: {latest}.")
```

## Recovery

**`backup-now.sh` exited non-zero during the pg_dump phase.**
One database failed to dump. The restic pass did NOT run. Check
`journalctl -u postgres` and `/var/backups/pg/` on the host. Fix the
offending DB (disk full? role missing?), then re-run this skill.

**`backup-now.sh` exited during `restic backup`.**
Usual culprit: Object Storage credentials rotated, bucket full, or a
stale restic lock. Check:
1. `ssh $HOST_NAME sudo restic unlock` if a prior run crashed.
2. `ssh $HOST_NAME sudo /opt/hetzbot/skills/infra/restic/review.sh`
   to verify creds + repo access.
Re-run this skill after resolving.

**`forget --prune` failed but backup succeeded.**
The new snapshot is safe. Prune will retry on the next timer run.
No action needed unless Object Storage is at quota.

**Snapshot count went backwards.**
Someone ran `restic forget` with an aggressive `--keep-*` in parallel.
Inspect with `restic snapshots` and confirm intent before acting.

## Rules

- **Never delete snapshots from this skill.** `restic forget` with
  non-default retention is out of scope — it's irreversible and
  should be a separate, deliberate operator action.
- **Don't run two backups concurrently on the same host.** Restic
  serializes via lock, but wait-locks waste wall time. If the timer
  is about to fire, let it.
- **This skill does not rotate restic creds.** If the backup fails
  because creds are wrong, fix `.env` + redeploy — don't work around
  it here.
