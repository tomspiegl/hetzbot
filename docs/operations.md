# Operations

Day-to-day. All commands run from the **fleet repo** (not hetzbot).

## Command reference

| Command | What it does |
|---|---|
| `just init` | Initialize tofu backend. Run once per fleet. |
| `just plan` | Preview infra changes. |
| `just apply` | Create/update hosts, firewall, DNS. |
| `just deploy <host>` | Push skills + services to a host. Idempotent. |
| `just deploy-dry <host>` | Preview rsync + SSH commands. |
| `just review <host>` | Severity-tagged audit. Exits 1 on HIGH, 2 on CRITICAL. |
| `just status` | Cross-host uptime + running units summary. |
| `just ssh <host>` | SSH via Tailscale MagicDNS. |
| `just logs <host> <service>` | Tail journald live. |
| `just backup <host>` | Force a backup run now. |
| `just snapshot <host>` | List restic snapshots for a host. |
| `just verify <host>` | End-to-end verification (backups, Postgres, timers, Google API). |
| `just rotate <host> <service>` | Rotate a service's Postgres password. |
| `just destroy` | Destroy the **entire** fleet. Rarely used; asks for confirmation. |

Preferred over raw `tofu` / `ssh` — they wrap the right env vars and
paths.

## Adding a host

Invoke the agent from the fleet repo:

> "Add a host in nbg1, cx22, headless."

The agent follows `skills/hetzner/add-host`:
1. Asks for name, location, type, public?.
2. Edits `hosts.tfvars`.
3. Asks you to generate a Tailscale auth key.
4. Runs `just apply`.
5. Waits for the host to join the tailnet.
6. Runs `just review`.

All interactive. Program-style — see [skills.md](skills.md).

## Adding a service

> "Add the myapi service from github.com/org/myapi, long-running,
> public-facing."

Agent follows `skills/ops/add-service`:
1. Asks for name, repo URL, target host, shape
   (long-running/scheduled), HTTPS-facing?.
2. Scaffolds `services/<name>/` (source, .service, .env.example,
   optional .timer + caddy.conf).
3. Adds the service to the host's `services` list in `hosts.tfvars`.
4. If public, `just apply` (creates DNS record).
5. `just deploy <host>` (clones, builds, provisions DB + .env,
   installs unit + hardening drop-in, starts).
6. `just review <host>`.

## Updating service code

- **Change the pinned SHA:** edit `services/<name>/source` to
  `<url>#<new-sha>`, then `just deploy <host>`.
- **Pull latest from tracked branch:** `just deploy <host>` alone —
  `install-service.sh` does `git fetch + checkout + reset --hard
  origin/<branch>` every deploy.

## Rolling back a service

Two paths:

- **Declarative (preferred):** edit `source` to a previous SHA, `just
  deploy`. The change is in git.
- **Imperative (emergency):** SSH in, check out the old SHA, restart:
  ```bash
  ssh <host>
  sudo -u <svc> git -C /srv/<svc>/repo checkout <sha>
  sudo bash /opt/hetzbot/services/<svc>/build.sh  # if present
  sudo systemctl restart <svc>
  ```
  Fix the `source` file afterward so `deploy` doesn't undo it.

## Rotating a secret

```bash
just rotate <host> <service>
```

Regenerates the Postgres password, issues `ALTER ROLE`, rewrites
`/srv/<svc>/.env` (preserving any other keys the service added),
restarts the unit. One command, zero downtime beyond the restart.

## Running a backup on demand

```bash
just backup <host>
```

Runs `backup-now.sh` immediately — same path as the 02:30 timer. Use
before a risky change, then restore the result if needed.

## Reviewing the fleet

```bash
just review <host>           # one host, full audit
just status                  # every host, quick status
```

`just review` runs every skill's `review.sh` and aggregates findings
by severity. Exit codes make it usable as a cron gate or CI check.

## Health check schedule

- **After `just apply`** — confirms cloud-init finished cleanly.
- **After every `just deploy`** — confirms the new state is safe.
- **Before `tofu destroy`** — sanity check what you're about to
  remove.
- **Monthly** — operator hygiene.

## Emergency access

If Tailscale itself is down (control plane outage, your laptop lost
its tailnet identity):

1. Hetzner web console → Server → open VNC.
2. Log in as `root` with `CONSOLE_ROOT_PASSWORD` from your personal vault.
3. Debug. Common: `systemctl status tailscaled`, `journalctl -u
   tailscaled`, `journalctl -u cloud-final`.

SSH on public IP is not an option — it was never enabled.

If the main OS won't boot:

1. `hcloud server enable-rescue --ssh-keys <op-key> <name>`.
2. Reboot; SSH as root to the rescue OS; mount `/dev/sda1`; edit what
   you need; reboot back to normal.

Both paths are documented in `skills/hetzner/remove-host/SKILL.md §
Recovery` for the specific failure modes.

## Versioning hetzbot

The fleet points at `$HETZBOT_ROOT` (a local clone of the framework).

```bash
# Track main
git -C $HETZBOT_ROOT pull --ff-only

# Pin a version
git -C $HETZBOT_ROOT checkout v0.3.0
```

After upgrading, run `just review <host>` for every host to see
what's changed.
