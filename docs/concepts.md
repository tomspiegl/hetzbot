# Concepts

## What hetzbot is

A reusable framework for running **1..n Hetzner Cloud hosts** with
**shared infra** (Postgres today; Redis, brokers later) and **your
services** (first-party code cloned from GitHub and run as systemd
units).

Two distinct repos:

- **`hetzbot`** — the framework. Skills + templates + docs. Public,
  reusable.
- **`<fleet>-infra`** — your fleet. `tofu/` + `hosts.tfvars` +
  `services/` + `.env`. One repo per fleet.

The agent (Claude Code) runs on your laptop, inherits your Tailscale
identity, and drives the framework's skills. Nothing autonomous — the
agent needs you in the shell.

## Headless by default

Fresh host exposes **nothing** to the public internet. Operator and
agent reach it over a Tailscale overlay. Opt in to HTTPS per host with
`public = true` in `hosts.tfvars`; that opens only 443. Port 80 is
never opened; plain HTTP is not an access path. Many fleets have zero
public hosts.

## One tool per job

- **OpenTofu** (not Terraform): the declarative shape of Hetzner —
  servers, firewall, DNS.
- **cloud-init**: host's first-boot config — joins Tailscale, locks
  down SSH, installs the minimal baseline.
- **systemd + git checkout**: how **your** services run. No
  Dockerfiles, no image registry, no tag bookkeeping.
- **Docker Compose**: how **third-party** daemons (Postgres) run.
  Narrow scope.
- **Tailscale**: operator access, MagicDNS, no public SSH.
- **Caddy** (on public hosts only): TLS termination on 443, ACME via
  TLS-ALPN-01. No port-80 listener.
- **restic**: encrypted backups to Hetzner Object Storage.

Each tool has one job. No aggregation layer, no framework wiring.

## Skills = agent playbooks + the scripts they invoke

Every skill lives at `skills/<group>/<skill>/` in the framework repo.
A skill may contain:

- `SKILL.md` — the playbook (always).
- `install.sh` — idempotent install for infra skills.
- `review.sh` — read-only audit; emits `[SEV] cat: msg` lines.
- `backup.sh` — pre-backup hook for stateful skills.
- Assets (e.g. `docker-compose.yml`).

Four groups:

| Group | What | Skills |
|---|---|---|
| `hetzner/` | cloud/server lifecycle | init-fleet, add-host, remove-host, check-fleet, review-host |
| `ops/` | service lifecycle verbs | add-service, remove-service, deploy, restore |
| `infra/` | installable daemons + stacks | docker, restic, caddy, postgres |
| `runtimes/` | language runtimes | node, python |

## Where things live on a host

```
/opt/hetzbot/skills/      framework code, rsynced by deploy.sh
/srv/<svc>/               per-service: repo checkout + .env + data
/etc/hetzbot/             host-local secrets (postgres super, restic env)
/var/lib/docker/volumes/  Postgres data
/var/backups/pg/          staging area for pg_dump
```

`/opt/hetzbot/` is **replaceable at any time** — `just deploy` rewrites
it. Real state lives in `/srv/`, `/etc/hetzbot/`, and Docker volumes.

## Guiding principles

- **Boring over clever.** Debian + systemd + Caddy + Docker — a stack
  every tutorial and LLM knows.
- **Safe by default.** Hardening is automatic. Services opt *out* of a
  constraint with a visible commit, never opt *into* safety.
- **Closed by default.** No public ports, no SSH keys, no HTTP.
- **Ceilings everywhere.** Logs, Docker images, backups — every growing
  source has retention from day one.
- **Simple now, upgrade paths named.** No OIDC, no self-hosted S3, no
  Prometheus today. When you need them: [non-goals](non-goals.md).

## When hetzbot is the wrong tool

- You need high availability — multi-region active/active, automatic
  failover. See [non-goals](non-goals.md).
- You host untrusted workloads. Per-service sandboxing isn't strong
  enough for multi-tenant SaaS.
- You need >10 hosts. `deploy.sh` iterates; past that, reach for
  Ansible.
- You're not comfortable with "rebuild from tofu + restic in an hour"
  as the recovery model.
