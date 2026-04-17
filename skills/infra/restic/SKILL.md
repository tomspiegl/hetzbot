---
name: hetzbot-restic
description: Install restic (backup tool) on a host. Triggers: any host that runs services (all of them). Installed on first deploy. Reads creds from /etc/hetzbot/restic.env written by cloud-init.
---

# restic

Apt-installed restic. Universal — every host runs the backup timer,
which calls `skills/ops/deploy/backup-now.sh`, which invokes
restic.

## Files

| File | Purpose |
|---|---|
| `install.sh` | `apt-get install -y restic`. Idempotent. |
| `review.sh` | Audits: restic binary present, `/etc/hetzbot/restic.env` populated, repo reachable, `restic check --read-data-subset 1%` passes monthly (not every review — optional). |

## How credentials flow

`/etc/hetzbot/restic.env` is written by cloud-init (tofu renders in
the Object Storage key/secret + `RESTIC_REPOSITORY` + `RESTIC_PASSWORD`
from `.env`). It's mode 0600. `backup-now.sh` is a systemd unit with
`EnvironmentFile=/etc/hetzbot/restic.env` — that's how the daemon
picks up credentials without any process ever reading them from the
filesystem at runtime.

## Review checks

- `CRITICAL` — restic not installed but services are deployed
  (backup timer would fail).
- `CRITICAL` — `/etc/hetzbot/restic.env` missing.
- `HIGH` — snapshot query fails (auth or repo issue).
- (Snapshot age + retention are reviewed by
  `skills/ops/deploy/review.sh`, since the timer lives there.)
