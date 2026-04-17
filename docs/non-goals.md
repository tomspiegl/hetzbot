<img src="../assets/icon.svg" alt="" width="48" align="left">

# Non-goals

What hetzbot deliberately doesn't do, and the named upgrade path for
each deferred choice.

## High availability

Single host per service. If a box dies, restore from tofu + cloud-init
+ restic. **Target cold-restore: under one hour.** No hot standby, no
active/active, no automatic failover.

**Upgrade path:** outside hetzbot. Put a load balancer (Hetzner LB or
Cloudflare) in front of two hosts running the same service pointing
at a shared managed Postgres. That's a different architecture —
hetzbot is single-host-per-service by design.

## Cross-host service dependencies

Each host owns its own Postgres. No shared DB across hosts — that
brings private networks, cross-host secrets, multi-host failure
modes, and migrations.

**Upgrade path:** a managed Postgres (Hetzner, Neon, Supabase, RDS).
Services connect via `DATABASE_URL` over the tailnet or a private
link. `skills/infra/postgres/` becomes redundant.

## NixOS-level OS reproducibility

Debian + `unattended-upgrades` means OS packages drift inside a
minor-version band. `services/<name>/source` commit pins + pinned
Docker image tags + pinned Node/uv versions are what's reproducible.
Atomic whole-host rollback is Hetzner snapshots, not the OS.

**Upgrade path:** NixOS / Flatcar / Talos. Fundamentally different
stack; hetzbot's boring-Debian assumption doesn't survive.

## Per-service runtime isolation

Native services share the host's installed Node / Python / etc. If two
services need different runtime majors, the second one moves to
`skills/infra/<name>/` as a containerized stack.

**Upgrade path:** Docker-first for first-party code. Write Dockerfiles,
push to a registry, pull at deploy. Doubles the deploy machinery
(registry auth, tag bookkeeping, image pruning) — only worth it when
runtime isolation is a frequent real need.

## Docker as the default for first-party code

Docker is narrowly scoped to third-party daemons (Postgres) where the
upstream image is clearly easier than packaging ourselves. Our code is
systemd + git.

**Upgrade path:** the per-service isolation path above.

## Multi-tenant auth / SSO

No shared OIDC today. Each service handles its own login.

**Upgrade path:** add **Pocket ID** or **Authelia** as an `infra/`
skill; front other services with Caddy's `forward_auth`. Probably ~2
hours to wire up when you actually need it.

## Self-hosted object store

S3-compatible needs are served by **Hetzner Object Storage** (managed).
No Garage or MinIO on-host.

**Upgrade path:** `infra/garage/` or `infra/minio/` skill if
vendor-neutrality matters. Adds one more thing to back up.

## Self-hosted observability stack

No Prometheus, Grafana, Loki, or Alertmanager. Healthchecks.io covers
"is it down"; **Netdata** (single-binary installer) covers "why" when
needed.

**Upgrade path:** if Netdata isn't enough, add a `infra/` skill
wrapping a small Prometheus + Grafana Compose stack. Don't build a
full observability platform — you're not Google.

## CI/CD pipelines

The agent plus the declarative flow is the deployment pipeline. No
GitHub Actions doing `terraform apply`.

**Upgrade path:** a hosted runner (GitHub Actions) that signs into
Tailscale under `tag:agent` and runs `just deploy` on merge. See
[security.md § Agent access model](security.md#operator-access) —
requires a dedicated Tailscale tag + ACL.

## Aggregator / framework for services

Services wire themselves explicitly. If and when duplication becomes
a concrete cost (a change needed in 10+ service files at once),
extract scripts — not before.

## Public SSH

Port 22 is never exposed to the internet. Operator access is Tailscale
SSH only.

**Upgrade path:** there isn't one worth taking. The tailnet scales.

## Plain HTTP

Port 80 is never opened. Even for redirects. HTTPS is the only access
path; ACME uses TLS-ALPN-01 on 443.

**Upgrade path:** don't. Clients that can't speak HTTPS in 2026 aren't
clients you want.

## A remove-fleet skill

`just destroy` exists (destroys all hosts in the current fleet). There
is no `remove-fleet` skill to automatically nuke the bucket, state,
Tailscale devices, DNS zone, Hetzner project. Too much blast radius
for a button.

**Upgrade path:** the documented manual sequence in this file.
