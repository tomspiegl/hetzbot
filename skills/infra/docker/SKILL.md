---
name: hetzbot-docker
description: Install Docker Engine + Compose plugin on a host. Triggers: install-service sees a skill needs to start a compose stack. Idempotent. Hardens the daemon (no-new-privileges, journald log driver, live-restore).
---

# docker

Apt-installed Docker from the official `download.docker.com` repo.
Required by every stateful skill that ships a `docker-compose.yml`
(currently: postgres).

## Files

| File | Purpose |
|---|---|
| `install.sh` | Adds Docker's signed-by apt repo; installs docker-ce + compose plugin; writes `/etc/docker/daemon.json` with hardening + journald logging; enables unattended-upgrades for the Docker origin. Idempotent. |
| `review.sh` | Audits: daemon active, daemon.json contains the expected hardening keys, NetworkManager not fighting over docker0. |

## Hardening

`/etc/docker/daemon.json` written by install.sh:

```json
{
  "log-driver": "journald",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true
}
```

- `log-driver: journald` — container logs flow into journald, covered
  by `SystemMaxUse=2G` and journald's rotation. No per-container log
  files piling up under `/var/lib/docker/containers/`.
- `live-restore: true` — containers keep running across `dockerd`
  restart (security patches, reboot). Brief control-plane outage; no
  data plane gap for running services.
- `userland-proxy: false` — avoid docker-proxy processes per
  published port (saves RAM + removes an attack surface).
- `no-new-privileges: true` — default for all containers; per-compose
  `security_opt` still respected.

## When `install.sh` runs

`deploy.sh` calls this first (before any `docker compose up`). Idempotent.

## Review checks

- `CRITICAL` — daemon not active.
- `HIGH` — `/etc/docker/daemon.json` missing a hardening key.
- `OK` — daemon active with expected config.
