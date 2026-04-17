---
name: hetzbot-postgres
description: Install and manage shared Postgres on a hetzbot host. Triggers: user says "install postgres", "provision a db for X", "rotate X's password", "restore X's database". Provides the Compose stack plus per-service provision/rotate/backup helpers.
---

# postgres

Pinned Postgres 16 as a Docker Compose stack. One instance per host.
Binds `127.0.0.1:5432`; runs as the image's non-root UID;
`no-new-privileges`; journald log driver. Per-service DBs + roles are
created on demand by `install.sh`.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | The stack. Pinned `postgres:16`. |
| `install.sh <svc>` | Idempotent: create DB + role + `/srv/<svc>/.env`. |
| `rotate.sh <svc>` | Rotate one service's password; rewrites `.env`; restarts unit. |
| `backup.sh` | Per-DB `pg_dump -Fc` to `/var/backups/pg/`. Invoked by `deploy/backup-now.sh`. |

## Install (first time on a host)

`skills/ops/deploy/deploy.sh` does this automatically:

1. Generates the Postgres superuser password on the host
   (`openssl rand`, written to `/etc/hetzbot/postgres_superuser`,
   mode 0600). Never leaves the host; not in a personal vault.
2. `cd /opt/hetzbot/skills/postgres && docker compose up -d --wait`.
3. Healthcheck passes when `pg_isready` succeeds.

## Per-service provisioning

When a service is added, `skills/ops/deploy/install-service.sh` calls
`install.sh <svc>` (unless the service ships its own
`services/<name>/provision.sh`). `install.sh`:

- creates a role named `<svc>` with a 32-hex password,
- creates a DB named `<svc>` owned by that role,
- writes `DATABASE_URL=postgres://<svc>:<pw>@127.0.0.1:5432/<svc>` to
  `/srv/<svc>/.env` (mode 0640, `root:<svc>`).

Idempotent — re-running detects an existing `.env` and exits.

## Rotation

``ssh <host> sudo /opt/hetzbot/skills/infra/postgres/rotate.sh <service>`` runs `rotate.sh` on the host. It
generates a new password, issues `ALTER ROLE`, rewrites `.env`,
restarts the systemd unit.

## Backup hook

`skills/ops/deploy/backup-now.sh` discovers `skills/infra/*/backup.sh` and runs
each before the restic pass. This skill's `backup.sh` writes one
`pg_dump -Fc` per database to `/var/backups/pg/<db>-YYYY-MM-DD.dump`.
Dumps older than 14 days are pruned from the host; restic retention
owns the long tail.

## Reusing the skill

`skills/infra/postgres/` is self-contained. Drop it into another
hetzbot-style fleet and it works — the only expectation is
`/opt/hetzbot/skills/ops/deploy/lib.sh` (shared helpers) and that the
stack can read `/etc/hetzbot/postgres_superuser`.
