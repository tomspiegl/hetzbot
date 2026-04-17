<img src="assets/logo.svg" alt="hetzbot" width="160">

Agent-managed hosting framework for Hetzner Cloud. You clone this repo,
scaffold a **fleet** repo beside it, and hand it to a coding agent
(Claude Code) — the agent provisions, deploys, backs up, reviews, and
tears down via documented skills. Declarative infra (OpenTofu),
Tailscale-only access, encrypted off-host backups (restic).

## Quickstart

**1. Clone this repo:**

```bash
git clone https://github.com/tomspiegl/hetzbot
```

**2. Open a coding agent in the same directory:**

```bash
claude   # Claude Code — https://claude.ai/code
# or
pi       # pi (pi.dev) — npm install -g @mariozechner/pi-coding-agent
```

**3. Paste this prompt:**

```
I'd like to set up a new hetzbot fleet named my-fleet at ~/my-fleet. First walk me through the external prerequisites. Then run the init-fleet skill to scaffold the fleet repo. Finally, guide me through adding my first host with add-host.
```

The agent reads `CLAUDE.md`, consults the relevant `SKILL.md` files,
and walks you through — one question at a time.

## Documentation

Full handbook in [`docs/`](docs/).
