---
name: hetzbot-postgres
description: Install and manage shared Postgres on a hetzbot host. Triggers: user says "install postgres", "provision a db for X", "rotate X's password", "restore X's database". Provides the Compose stack plus per-service provision/rotate/backup helpers.
---

# postgres

Postgres as a Docker Compose stack, **per-host configurable** image and
extra packages. One instance per host. Binds `127.0.0.1:5432`; runs as
the image's non-root UID; `no-new-privileges`; journald log driver.
Per-service DBs + roles are created on demand by `install.sh`.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Layered image — takes `BASE` and `EXTRA_PKGS` build args; apt-installs the extras on top of the base image. |
| `docker-compose.yml` | The stack. `build:` from local Dockerfile so each host can pin its own version + extensions. Built tag is `hetzbot-postgres:local`. |
| `install.sh <svc>` | Idempotent: create DB + role + `/srv/<svc>/.env`. |
| `rotate.sh <svc>` | Rotate one service's password; rewrites `.env`; restarts unit. |
| `backup.sh` | Per-DB `pg_dump -Fc` to `/var/backups/pg/`. Invoked by `deploy/backup-now.sh`. |

## Per-host configuration

Two optional fields in `hosts.tfvars`:

```hcl
hetz-2 = {
  ...
  postgres_image      = "pgvector/pgvector:pg17"      # default: pg16
  postgres_extra_pkgs = "postgresql-17-partman"        # default: ""
}
```

`deploy.sh` reads these from `tofu output` and exports them as
`POSTGRES_IMAGE` / `POSTGRES_EXTRA_PKGS` for the `docker compose up
--build` invocation. The image is rebuilt locally on the host (no
external registry), so pulling stays inside Hetzner for the base image
and apt-getting stays on the Debian mirror.

**Major-version upgrades** (e.g. pg16 → pg17) are not in-place: the
PGDATA directory format differs across majors. Plan for a dump/restore
cycle on hosts with live data before changing `postgres_image`.

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
