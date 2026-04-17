<img src="../assets/logo.svg" alt="hetzbot" width="240">

# hetzbot handbook

Agent-managed Hetzner Cloud hosting. Drop in a fleet repo; add hosts;
add services; deploy. Operator runs `claude` from the fleet directory;
the agent handles the rest.

## Read in order

1. [Concepts](concepts.md) — what hetzbot is, the mental model, when
   it fits (and when it doesn't).
2. [Architecture](architecture.md) — pieces + flow, diagrams.
3. [Quickstart](quickstart.md) — zero to first running service.
4. [Skills](skills.md) — catalog, when to invoke each.
5. [Security](security.md) — the default posture, what's locked down.
6. [Backups](backups.md) — what's backed up, how to restore.
7. [Operations](operations.md) — daily commands, common tasks.
8. [Non-goals](non-goals.md) — what we deliberately don't do, and
   each deferred choice's named upgrade path.

## Jump to

- **"I want to set up a new fleet."** → [quickstart](quickstart.md).
- **"I want to add a host / service."** → [skills](skills.md) + invoke
  the matching skill.
- **"Something feels broken."** → `just review <host>`; see
  [operations](operations.md).
- **"Is this safe to expose?"** → [security](security.md).
- **"A host is gone. Now what?"** → [backups](backups.md) § recovery.

## What this is not

- A tutorial for Hetzner Cloud, Tailscale, systemd, or Docker. Those
  each have their own docs.
- A Kubernetes / HA alternative. See [non-goals](non-goals.md).
- A production hosting platform for untrusted workloads. Everything
  here assumes you own both the framework and the services.
