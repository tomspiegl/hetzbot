---
name: hetzbot-node
description: Install Node.js LTS on a host with hardened npm defaults. Triggers: user says "install node", "add node runtime", or install-service.sh detects `package-lock.json`. Idempotent.
---

# node

Installs Node.js LTS (currently 20) from the official NodeSource apt
repo, plus host-wide `/etc/npmrc` with supply-chain defaults. Runs
on-demand, not in cloud-init.

## What `install.sh` does

1. **Early-exit** if `node --version` already satisfies the pinned
   major. Idempotent — safe to call on every deploy.
2. **Adds NodeSource** with a `signed-by:` keyring under
   `/etc/apt/keyrings/nodesource.gpg`. Never `apt-key add` (deprecated).
3. **`apt-get install -y nodejs`** pulls Node + npm together from the
   single NodeSource package.
4. **Writes `/etc/npmrc`** — host-wide default:
   ```
   ignore-scripts=true
   fund=false
   audit-level=high
   ```
5. **Registers NodeSource with unattended-upgrades** via a drop-in at
   `/etc/apt/apt.conf.d/51unattended-upgrades-nodesource` so security
   releases land nightly.

## Security posture — how Node stays safe here

**`ignore-scripts=true` is the keystone.** Malicious npm packages
almost always land their payload in a `postinstall` / `preinstall`
lifecycle script. With this set, `npm ci` will install the tree
without executing any of those scripts. Package *code* still runs
when the service imports it — that's a separate risk, managed by the
service repo's CI (see below).

**Lockfile required.** `install-service.sh` refuses to deploy a
Node service without `package-lock.json`. The lockfile has integrity
hashes; `npm ci` verifies them against the downloaded tarballs.

**`npm ci --ignore-scripts` is the default build.** No `npm install`
ever runs at deploy time (would mutate the lockfile). Services that
legitimately need a lifecycle script (node-gyp, prisma, sharp) add a
repo-local `.npmrc` that overrides `ignore-scripts=false` for that
specific package scope — visible, reviewable, scoped.

**Supply-chain scanning is owned by the service repo's CI.** Each
first-party service runs `npm audit --audit-level=high` as a PR gate on its
own GitHub Actions; Dependabot/Renovate opens bump PRs. The host
doesn't scan — by the time code reaches the deploy path, its CI has
approved it. Centralizing scanning here would duplicate work and
slow deploys.

**npm itself.** The NodeSource package includes a pinned npm. We
don't `npm install -g npm@latest` — privileged auto-updates of the
package manager are themselves a supply-chain surface. NodeSource's
security releases cover npm.

**Node version bumps.** Pin `NODE_MAJOR` in `install.sh` (currently
`20`). When LTS transitions (e.g., 20 → 22), update this value once,
redeploy, test. Coordinate across services — a runtime major bump
is fleet-wide.

## When it runs

- First deploy of any Node service to a host.
- Any deploy, idempotently — if already installed, exits in ~10ms.
- Never from cloud-init (deliberately — hosts that run no Node
  services never install Node).

## What the reviewer checks

`skills/hetzner/review-host/review.sh` flags:
- `HIGH` — `/etc/npmrc` missing or lacks `ignore-scripts=true`.
- `MEDIUM` — `audit-level=high` absent.
- `HIGH` — a service on the host has `package-lock.json` but `node`
  is absent (deploy would fail).
- `LOW` — Node major version is past end-of-life.
