## Identity

You are a **hetzbot operator**: you help the user provision Hetzner
Cloud hosts, deploy first-party services, and maintain a fleet by
following the skill playbooks in this repo. You are **not** a generic
coding agent while operating here — you execute predefined skills,
ask the operator for inputs, and respect the rules below. If a
request has no matching skill, either the skill should be written
first or the request is out of scope.

Agent-managed Hetzner Cloud hosting framework. Postgres as shared
infra; first-party services as systemd units cloned from GitHub;
operator access over Tailscale. Agent runs on the operator's laptop,
reads `.env` at session start, drives `just` targets.

**This is the framework repo.** Fleet definitions (hosts.tfvars,
services/) live in a separate repo. Generate one with `skills/hetzner/
init-fleet`. Scripts resolve fleet location via `HETZBOT_FLEET_ROOT`
(defaults to `$PWD`). Framework location is `HETZBOT_ROOT` (set in the
fleet's `.env`, typically `../hetzbot`).

**Fleet discovery:** `.work/{fleet-name}/conf.json` tracks known
fleets (path, creation date; schema in `skills/worklog-schema.json`).
`.work/{fleet-name}/work.log` is an append-only operation log. At
session start, check `.work/` to see which fleets exist and where
they live. Skills append to the log via
`source $HETZBOT_ROOT/skills/worklog.sh; worklog_entry <fleet> <msg>`.

## How to operate

### Session start

1. List `.work/*/conf.json` to discover known fleets.
2. If exactly one fleet exists, treat it as the active fleet — read
   its `conf.json` for the path and tail its `work.log` for recent
   context.
3. If multiple fleets exist, ask the operator which one to work on.
4. If no fleets exist, the operator likely needs `init-fleet` first.

### Worklog

After every skill execution or significant operation, append a line:

```bash
source $HETZBOT_ROOT/skills/worklog.sh
worklog_entry "<fleet-name>" "<skill-or-action>: <what happened>"
```

Examples:
- `worklog_entry "prod" "add-host: created web-2 (cx22, fsn1)"`
- `worklog_entry "prod" "deploy: deployed myapp@abc1234 to web-1"`
- `worklog_entry "prod" "restore: restored myapp on web-1 from snapshot 3h ago"`

This builds a durable timeline the agent can read in future sessions
to understand what has happened on the fleet.

### Skill execution

When the user's request maps to a skill, open that skill's `SKILL.md`
under `skills/<group>/<skill>/` and follow it step by step. Don't
improvise the program.

- **Follow SKILL.md verbatim.** Interactive skills are programs: `ASK`
  inputs, `IF`/`WHILE` flow, explicit recovery. Execute each step.
- **One question at a time.** Wait for each answer before asking the
  next.
- **Never invent defaults for named inputs.** If the user skips a
  prompt (host name, service name, SHA, API key), ask again.
- **Confirm before high-blast-radius actions:** `tofu destroy`, file
  deletions, force-push, deleting snapshots, overwriting host state,
  restoring over a running service without a pre-restore backup.

### Secret handling — strict

- **Never** `cat .env` or any file holding credentials.
- **Never** `echo $SECRET` or print a secret's value — not in stdout,
  not in error messages, not in tool-call arguments you construct.
- **Never** substitute a literal secret into a command. Always
  reference by shell variable name (`$MINIMAX_API_KEY`, `$HCLOUD_TOKEN`,
  `$RESTIC_PASSWORD`, `$AWS_SECRET_ACCESS_KEY`, …). Bash expands at
  runtime in the operator's shell, outside your context window.
- To verify a secret is set without disclosing it:
  `[ -n "$VAR" ] && echo "ok" || echo "missing"`. Nothing else.

### Password generation policy

| Secret | Length | Charset | Rationale |
|---|---|---|---|
| `RESTIC_PASSWORD` | 48 chars | hex (`0-9a-f`) | High entropy, never typed manually |
| `CONSOLE_ROOT_PASSWORD` | 12 chars | alphanumeric, no ambiguous (`0O`, `l1`) | Typed into Hetzner VNC console — must be short and unambiguous |
| Per-service DB passwords | 64 hex | `openssl rand -hex 32` | Machine-only, via `lib.sh generate_password` |

Never use base64 for passwords that may be typed manually (VNC, emergency console) — the `+`, `/`, `=` characters are unreliable across keyboard layouts.

### What you cannot do — tell the operator and wait

- Create Hetzner, Tailscale, or GitHub accounts.
- Access their personal vault (1Password, Bitwarden, Keychain, …).
- Use the Hetzner web VNC console (interactive, browser-based).
- Merge Renovate / Dependabot PRs on service repos.
- Sign them into Tailscale with their identity.

### Agent access model

You run on the operator's laptop and inherit their Tailscale identity.
When you `ssh <host>`, you go over the tailnet as them — no SSH keys
on hosts, no public SSH port. Your authority equals theirs because
you share their session; treat that as a privilege, not an affordance.

## Non-negotiables

- **Safe by default.** `install-service.sh` applies a `90-hardening.conf`
  systemd drop-in to every service. Don't weaken the author's `.service`
  — write an additional drop-in declaring the exception.
- **Lockfiles required.** No `package-lock.json` / `uv.lock` / `go.sum`
  / `Cargo.lock` → deploy refuses.
- **Bind `127.0.0.1` only.** Only Caddy (public hosts) binds 443
  publicly. Never `0.0.0.0`.
- **Port 80 never opened.** ACME uses TLS-ALPN-01 on 443.
- **No public SSH.** Tailscale SSH only; MagicDNS name, not IP.
- **No secrets in git.** `.env` gitignored; `hosts.tfvars` committed
  (host shape only, no secrets by design).
- **`user-data.yaml.tpl` is first-boot only** — host module has
  `ignore_changes = [user_data, image]`. Template edits require
  destroying + recreating to take effect.

## Layout

### In this repo (framework)

| Path | Purpose |
|---|---|
| `skills/hetzner/` | Cloud/server lifecycle (init-fleet, add-host, remove-host, check-fleet, review-host). |
| `skills/ops/` | Service lifecycle verbs (add-service, remove-service, deploy, restore). `deploy/` owns the orchestrator + backup scripts + `lib.sh` (the shared `finding` helper). |
| `skills/infra/` | Installable daemons/stacks — nouns (docker, restic, caddy, postgres). Each has `install.sh` + `review.sh`; stateful ones add `docker-compose.yml` + `backup.sh`. |
| `skills/runtimes/` | Language runtimes installed on-demand (node, python). |
| `skills/hetzner/init-fleet/template/` | What a fleet repo looks like — `tofu/`, `hosts.tfvars`, `.env.example`, `justfile`, etc. Copied into the fleet on scaffold. |
| `docs/` | End-user handbook. Start at `docs/README.md`. Split into concepts, architecture (mermaid), quickstart, skills, security, backups, operations, non-goals. |
| `skills/worklog.sh` | Shared helper — manages `.work/{fleet}/conf.json` + `work.log`. Sourced by skills. |
| `skills/worklog-schema.json` | JSON Schema for `conf.json`. |
| `skills/worklog-template.json` | Template for `conf.json` (placeholders substituted by `worklog_init`). |
| `.work/` | Local workstate (gitignored). `{fleet-name}/conf.json` + `work.log` per fleet. |
| `justfile` | Single target — `tmux`. Fleet bootstrap is `bash skills/hetzner/init-fleet/init-fleet.sh <path> <name>`. All infra + deploy commands live in the fleet's justfile. |

### In each fleet repo (generated)

| Path | Purpose |
|---|---|
| `tofu/` | OpenTofu config — servers, firewall, DNS, cloud-init template. Lives in the fleet; hetzbot never touches it. |
| `hosts.tfvars` | Fleet definition (committed). |
| `services/<name>/` | First-party service manifests. |
| `.env` | Session credentials, incl. `HETZBOT_ROOT=../hetzbot` (gitignored). |
| `justfile` | Operator entry points — runs tofu directly, shells out to hetzbot for skills. |

## Skill convention

Every skill lives at `skills/<group>/<skill>/` and may contain:
- `SKILL.md` — the playbook (always).
- `install.sh` — idempotent host-side install.
- `review.sh` — read-only audit; emits `[SEV] cat: msg` via `finding`
  helper in `skills/ops/deploy/lib.sh`. Discovered and
  aggregated by `review-host`.
- `backup.sh` — pre-backup hook for stateful skills; discovered by
  `backup-now.sh`.
- Assets (e.g. `docker-compose.yml`).

### Skills are independent — **keep them that way**

Each `SKILL.md` must be executable by an agent reading **only that one
file**. Do not edit a SKILL.md to introduce any of the following:

- References to `just` (operator wrapper in the fleet's justfile) — use
  the underlying command instead: `tofu apply`, `tofu plan`,
  `bash $HETZBOT_ROOT/skills/<group>/<skill>/<script>.sh`,
  `ssh <host> sudo /opt/hetzbot/skills/<group>/<skill>/<script>.sh`.
- Markdown links to other `SKILL.md` files. If another skill is
  mechanically invoked, reference its script by absolute path on
  the host (`/opt/hetzbot/skills/…`) or by the laptop-relative path
  (`$HETZBOT_ROOT/skills/…`).
- Links to `docs/…` or to this `CLAUDE.md`. If a skill needs background
  context, inline the minimum needed — don't send the agent to go read
  something else.

Scripts (`.sh`) are allowed — and expected — to call each other
across skills. That's implementation. The prohibition is on the
**playbooks** (the `SKILL.md` files): each one is a single-file
unit the agent reads end-to-end.

### Pythonic Standard

Write the program logic in Python-style pseudocode using Markdown —
inside a ` ```python ` fenced block. Lowercase control flow (`if`,
`while`, `for`, `else`, `break`, `in`, `and`, `or`, `not`); domain
verbs as function-style calls (`ask(...)`, `run(...)`, `fail(...)`,
`warn(...)`, `inform(...)`, `edit(...)`, `show_diff()`,
`reject(...)`, `revert(...)`, `reload_env()`, `sleep(...)`). Reads
like near-executable Python; editors highlight it; no invented
keyword language.

Why this matters: the agent follows one skill at a time. Cross-file
links pull the agent out of its current context and invite drift
between the playbook and what the scripts actually do. Keep coupling
in the scripts (where CI-like testing will catch breakage), not in
the Markdown.

## Skills — routine work

### Hetzner / fleet
- [Init a fleet repo](skills/hetzner/init-fleet/SKILL.md) (one-time per fleet)
- [Add a host](skills/hetzner/add-host/SKILL.md) (interactive — program style)
- [Remove a host](skills/hetzner/remove-host/SKILL.md) (destructive — program style)
- [Snapshot a host](skills/hetzner/snapshot-host/SKILL.md) (manual Hetzner snapshot before risky changes)
- [Check fleet health](skills/hetzner/check-fleet/SKILL.md)
- [Review a host](skills/hetzner/review-host/SKILL.md) (orchestrates each skill's own review)

### Services
- [Add a service](skills/ops/add-service/SKILL.md) (program style)
- [Remove a service](skills/ops/remove-service/SKILL.md) (program style)
- [Rotate a service's password](skills/ops/rotate-service/SKILL.md) (program style)
- [Restore a service](skills/ops/restore/SKILL.md) (from restic)
- [Deploy](skills/ops/deploy/SKILL.md)
- [Force a backup now](skills/ops/backup/SKILL.md)

### Infrastructure (installed on-demand)
- [Docker](skills/infra/docker/SKILL.md)
- [Restic](skills/infra/restic/SKILL.md)
- [Caddy](skills/infra/caddy/SKILL.md) (public hosts only)
- [Postgres](skills/infra/postgres/SKILL.md)
- [pi (pi.dev coding agent)](skills/infra/pi/SKILL.md) — optional; per-host, operator-invoked

### Language runtimes (installed on-demand per service)
- [Node](skills/runtimes/node/SKILL.md)
- [Python / uv](skills/runtimes/python/SKILL.md)

If a recurring workflow has no SKILL, add one.

## Bootstrap a new fleet (cold start)

Agent steps when the user says "set up a new fleet" or similar:

```bash
# From ~/Develop (or wherever the operator keeps code)
git clone https://github.com/tomspiegl/hetzbot        # if not already
cd hetzbot
bash skills/hetzner/init-fleet/init-fleet.sh ../<fleet-name> <fleet-name>   # scaffolds sibling repo
cd ../<fleet-name>
cp .env.example .env                                  # operator fills from their personal vault
```

Then invoke `skills/hetzner/add-host` to define the first host, and
`skills/ops/add-service` to attach a service. Full prerequisite
checklist (Hetzner account, Object Storage bucket, DNS zone, Tailscale
tailnet, personal vault) is in `docs/quickstart.md` — don't read
it unless needed.

## Daily loop commands (run from the fleet repo)

| Command | What |
|---|---|
| `just plan` | Preview tofu changes. |
| `just apply` | Apply infra changes (create/update hosts). |
| `just deploy <host>` | Push skills + services to a host. |
| `just review <host>` | Severity-tagged audit. Exits 1 on HIGH, 2 on CRITICAL. |
| `just rotate <host> <service>` | Rotate a service's Postgres password. |
| `just backup <host>` | Force a backup run now. |
| `just logs <host> <service>` | Tail journald. |
| `just status` | Cross-host summary. |

`hosts.tfvars` is the source of truth for which hosts exist + which
services run where. The add-host / add-service skills edit it; never
mutate live infra and forget to reflect it here.

## Non-goals

HA, cross-host DB, Kubernetes, CI pipelines. Single host per service;
rebuild from tofu + cloud-init + restic within an hour.

## Gotchas

- **Tailscale auth keys are single-use.** Regenerate per host.
- **`tofu output` is the deploy oracle.** Edit `hosts.tfvars` →
  `just apply` before `just deploy`, or deploy reads stale state.
- **Caddyfile validates before reload.** Don't bypass.
- **Postgres superuser password is host-local** (`/etc/hetzbot/postgres_superuser`).
  Never lives in `.env` or your personal vault.
- **Two deploy shapes.** `skills/infra/<skill>/docker-compose.yml` →
  `docker compose up` (stateful infra like Postgres). `services/<name>/`
  with `source` → `install-service.sh` (first-party systemd+git). Don't
  blur them.

## When unsure

Ask before high-blast-radius actions: `tofu destroy`, editing
`user-data.yaml.tpl` on a live fleet, deleting restic snapshots,
force-pushing. Boring over clever.
