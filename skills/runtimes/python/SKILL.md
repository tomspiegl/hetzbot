---
name: hetzbot-python
description: Install uv (Astral's Python package manager) with safe defaults. Triggers: user says "install python runtime", or install-service.sh detects `uv.lock`. Python itself ships with Debian; this skill adds `uv`. Idempotent.
---

# python

Installs `uv` from Astral to `/usr/local/bin/uv` on the host. **uv is
the runtime** — it downloads and manages whatever Python version each
service declares in its `pyproject.toml` (`requires-python`) or
`.python-version`. Services never use the system `/usr/bin/python3`,
which exists only for OS tooling (apt, unattended-upgrades). Each
service gets its own pinned Python, managed by uv.

## Why uv (and not pip/poetry/pipenv)

- **Lockfile-first.** `uv.lock` carries integrity hashes and resolves
  deterministically. `uv sync --locked` verifies hashes on every
  install; refuses to run if the lock is stale relative to
  `pyproject.toml`.
- **Wheel-preferred.** uv prefers binary wheels over sdists. That
  matters for safety — sdist installs execute arbitrary `setup.py`
  code at install time (Python's equivalent of npm postinstall).
  Wheels are pre-built, don't execute install-time code.
- **Build isolation.** When uv does fall back to an sdist, it builds
  in an isolated environment — the sdist's `setup.py` can't write to
  the target venv during install.
- **Fast.** Resolves in seconds; matters when `install-service.sh`
  runs `uv sync` on every deploy.

## What `install.sh` does

1. **Early-exit** if `uv --version` already succeeds. Idempotent.
2. **Downloads** the installer from `https://astral.sh/uv/install.sh`
   and runs it; uv binary ends up in `/root/.local/bin/uv`.
3. **Moves** it to `/usr/local/bin/uv` so every service user can run
   it from PATH.
4. No explicit Python install. uv fetches the exact Python version
   each service needs on first `uv sync`, cached under
   `~/.local/share/uv/python/`. Debian's `python3` is left alone.

## Security posture — how Python stays safe here

**Lockfile required.** `install-service.sh` refuses to deploy a
Python service without `uv.lock`. `uv sync --locked` then verifies
the hashes in the lock against the downloaded wheels/sdists.

**`uv sync --locked` is the default build.** Not `uv sync` (which
re-resolves). Not `pip install -r requirements.txt` (no hash
verification). The locked flag is the keystone — it refuses to
deploy if the lockfile is stale, matching the `npm ci` behavior.

**Wheel preference closes the `setup.py` hole.** The Python
equivalent of npm's postinstall problem is sdist `setup.py` running
arbitrary code during install. By defaulting to wheels, uv avoids
this path for the large majority of packages. For packages that only
ship sdists (rare for well-maintained libraries), uv's build
isolation contains the execution to a temporary environment.

**Virtual environments are per-service.** uv creates
`/srv/<svc>/repo/.venv/` owned by the service user. Systemd's
`ReadWritePaths=/srv/<svc>` keeps the venv writable; everything else
is read-only from the service's perspective.

**Supply-chain scanning is owned by the service repo's CI.** Each
Python service runs `pip-audit` (or uv's equivalent once it ships)
as a PR gate on its own GitHub Actions; Dependabot tracks Python
deps via `pyproject.toml`. The host doesn't scan — same rationale
as Node.

**uv self-updates.** Don't run `uv self update` in production;
upgrades happen via this skill's `install.sh` on deliberate change.
Pin the uv version later if drift becomes an issue.

## When it runs

- First deploy of any Python service to a host.
- Any subsequent deploy (idempotent; exits fast if already installed).
- Never from cloud-init.

## What the reviewer checks

`skills/runtimes/python/review.sh` flags:
- `HIGH` — a service has `uv.lock` but `uv` is absent (deploy would fail).
- `HIGH` — a service has `pyproject.toml` without `uv.lock`.
- `MEDIUM` — a service has `requirements.txt` instead of `uv.lock`
  (no hash verification path).
- `LOW` — `uv` version is more than a major behind latest.
