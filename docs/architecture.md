<img src="../assets/icon.svg" alt="" width="48" align="left">

# Architecture

How the pieces fit.

## Two repos

```mermaid
graph LR
    F[hetzbot repo<br/>framework] -. HETZBOT_ROOT .-> L[Fleet repo<br/>tofu/, hosts.tfvars,<br/>services/, .env]
    L -->|tofu apply| H[Hetzner Cloud API]
    L -->|just deploy<br/>over Tailscale| N[Host]
    F -. rsynced to .-> N
```

- **Framework (`hetzbot`)** — skills, templates, docs. One clone per
  operator laptop.
- **Fleet** — everything project-specific: tofu config, hosts,
  services, credentials. One repo per fleet.

The fleet points at the framework via `HETZBOT_ROOT=../hetzbot` in its
`.env`. All scripts accept `HETZBOT_FLEET_ROOT` (default `$PWD`) to
locate fleet data at runtime.

## Network topology

```mermaid
graph TB
    subgraph Op[" "]
        L[Operator laptop<br/>+ agent]
    end
    subgraph TSN["Tailscale tailnet (OIDC-gated, WireGuard)"]
        direction LR
        L
        H1[hetz-1<br/>public=true]
        H2[hetz-2<br/>headless]
    end
    I[Public internet] -->|only 443| H1
    I -.x no access.-> H2
    L -->|tofu apply| API[Hetzner Cloud API]
    API --> H1
    API --> H2
```

Operator never uses a public SSH port. Only `public = true` hosts
expose anything to the internet — and only 443. Port 80 is never
opened anywhere.

## Host runtime

What actually runs on one host after cloud-init + first deploy:

```mermaid
graph TB
    subgraph Host["Host (Debian 12)"]
        direction TB
        subgraph Boot["Installed by cloud-init"]
            TS[tailscaled]
            UFW[ufw — deny by default]
            SSH[sshd — Tailscale-only]
            UU[unattended-upgrades]
        end
        subgraph Skills["Installed by skills on first deploy"]
            D[docker-ce + compose]
            RS[restic]
            CD["caddy (public hosts)"]
            NR[node / uv]
        end
        subgraph SvcRuntime["Running (per service)"]
            S1[systemd unit + 90-hardening drop-in]
            S2["/srv/<svc>/repo"]
            S3["/srv/<svc>/.env"]
        end
        subgraph Infra["Stateful infra (compose)"]
            PG["postgres:16<br/>127.0.0.1:5432"]
        end
    end
```

Cloud-init installs only the bootstrap minimum — enough to join the
tailnet and accept rsync. Everything else is a skill, installed at
first deploy.

## Deploy flow

```mermaid
sequenceDiagram
    participant O as Operator
    participant L as Laptop (agent)
    participant T as tofu
    participant H as Host
    O->>L: just deploy hetz-1
    L->>T: tofu output -json hosts
    T-->>L: host config (public, services)
    L->>H: rsync skills/ → /opt/hetzbot/skills/
    L->>H: rsync services/<svc>/ → /opt/hetzbot/services/<svc>/
    L->>H: infra/docker/install.sh (idempotent)
    L->>H: infra/restic/install.sh (idempotent)
    L->>H: docker compose up -d (for each infra/*/compose)
    loop per service
        L->>H: ops/deploy/install-service.sh <svc> <source>
        H->>H: git clone / pull, build, provision DB, install unit
    end
    opt if public
        L->>H: infra/caddy/install.sh + assemble.sh
    end
```

Every step is idempotent. Re-running deploy is safe and cheap.

## Backup flow

```mermaid
graph LR
    T[systemd timer<br/>02:30 daily] --> B[ops/deploy/backup-now.sh]
    B --> Hooks[[Discover and run<br/>each skills/infra/#42;/backup.sh]]
    Hooks --> PGBackup[postgres/backup.sh<br/>pg_dump -Fc per DB]
    PGBackup --> D[/var/backups/pg/*.dump]
    B --> R[restic backup]
    D --> R
    SRV[/srv /var/lib/docker /etc .../] --> R
    R --> OS[Hetzner Object Storage<br/>encrypted at rest]
```

Each stateful skill ships its own `backup.sh`. `backup-now.sh` is a
thin orchestrator — it runs every hook, then does one restic pass over
the well-known paths.

## Skill composition

```mermaid
graph TB
    S[skills/]
    S --> HET[hetzner/<br/>cloud lifecycle]
    S --> OPS[ops/<br/>service verbs]
    S --> INF[infra/<br/>installable daemons]
    S --> RUN[runtimes/<br/>languages]
    HET --> H1[init-fleet]
    HET --> H2[add-host]
    HET --> H3[remove-host]
    HET --> H4[check-fleet]
    HET --> H5[review-host]
    OPS --> O1[add-service]
    OPS --> O2[remove-service]
    OPS --> O3[deploy]
    OPS --> O4[restore]
    INF --> I1[docker]
    INF --> I2[restic]
    INF --> I3[caddy]
    INF --> I4[postgres]
    RUN --> R1[node]
    RUN --> R2[python/uv]
```

- **hetzner/** — agent playbooks for managing Hetzner Cloud resources
  (VMs, firewall, DNS).
- **ops/** — service lifecycle. These are cross-cutting; they invoke
  infra/ and runtimes/ skills as needed.
- **infra/** — third-party daemons. Each is self-contained; has its
  own `install.sh`, `review.sh`, optionally `backup.sh` and
  `docker-compose.yml`.
- **runtimes/** — language runtimes. Installed on-demand when
  `install-service.sh` detects a lockfile.

See [skills.md](skills.md) for the catalog with usage notes.

## State — what lives where

```mermaid
graph TB
    subgraph FS["File system layers"]
        TF[tofu state<br/>Object Storage, encrypted]
        RES[restic repo<br/>Object Storage, encrypted]
        ENV[.env + personal vault<br/>operator laptop only]
    end
    subgraph Source["Source of truth"]
        GIT[Fleet git repo<br/>hosts.tfvars, services/]
        FRAMEWORK[hetzbot git repo<br/>skills/]
        SERVICES[Service GitHub repos<br/>code]
    end
    GIT --> TF
    FRAMEWORK -. rsynced to .-> HOST[/opt/hetzbot/skills/]
    SERVICES -. cloned to .-> HOSTSVC[/srv/&lt;svc&gt;/repo]
    HOST --> RES
    HOSTSVC --> RES
```

- **Infra state** — tofu state file in Object Storage.
- **Data state** — restic snapshots in Object Storage.
- **Config state** — committed in the fleet repo.
- **Session creds** — local `.env`, populated from your personal vault per
  session, cleared after.

Rebuild-from-zero sequence: `tofu apply` → cloud-init → `just deploy` →
`restic restore`.
