---
name: hetzbot-pi
description: Optional — install and configure the pi.dev coding agent on a host, defaulting to the Minimax model. Triggers: user says "install pi on <host>", "set up pi", "enable the coding agent on <host>". Interactive — asks whether to use Minimax, waits for the API key in an env file, installs the binary, writes /etc/hetzbot/pi.env. Agent must never read or echo the API key value.
---

# pi

Optional host-side skill. Installs the
[pi coding agent](https://pi.dev/) (`@mariozechner/pi-coding-agent`)
and configures it to use **Minimax** by default (a single
`MINIMAX_API_KEY` is the whole requirement). The operator can pick
another provider instead; the skill falls back to pointing at the
upstream docs.

> **For pi-specific provider names, config file location, or
> non-Minimax provider details not covered here, read:**
> - https://pi.dev/
> - https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent

## Secret-handling rule — READ FIRST

`MINIMAX_API_KEY` is a secret. The **agent must never see its value**:

- ❌ Do **not** `cat .env` / `cat ~/.config/hetzbot/keys.env` / any
  file the operator uses to hold the key.
- ❌ Do **not** `echo $MINIMAX_API_KEY` or print it anywhere.
- ❌ Do **not** substitute the literal key text into a command. Always
  reference it as the shell variable `$MINIMAX_API_KEY` — bash
  expands it at runtime, in the operator's shell, outside the LLM's
  context.
- ✅ Verify presence only with `[ -n "$MINIMAX_API_KEY" ] && echo "ok"
  || echo "missing"` — never with any command that prints the value.

Every step below is written so the variable passes from the
operator's shell → ssh stdin → the host, never through the LLM's
context window.

## Inputs

| Variable      | Prompt                                               | Constraint |
|---------------|------------------------------------------------------|------------|
| `TARGET_HOST` | Which host?                                          | must exist in `hosts.tfvars` |
| `USE_MINIMAX` | Use Minimax as pi's default provider?                | `yes` / `no` — default `yes` |

## Steps

### 1. Ask whether to use Minimax

> "Use Minimax as pi's default provider? (yes / no — picking no means
> you'll consult the upstream pi docs to set up another provider.)"

On `no`: tell the operator to follow the upstream docs and stop this
skill. It only automates the Minimax path.

### 2. Wait for the operator to provide the key

Instruct the operator:

> Put `MINIMAX_API_KEY=<your-key>` into either:
> - the fleet's `.env` (gitignored — this is the typical place), or
> - any other file you prefer (e.g. `~/.config/hetzbot/keys.env`).
>
> Then make sure the current shell has it exported. If you used the
> fleet's `.env`, `set dotenv-load := true` in the justfile takes
> care of it. Otherwise `source <yourfile>` before running the next
> step.
>
> Press enter when done.

Verify presence **without reading the value**:

```bash
[ -n "${MINIMAX_API_KEY:-}" ] && echo "ok" || echo "missing"
```

If `missing`: ask the operator to retry (either re-source or re-edit
`.env`). Never attempt to read the file yourself.

### 3. Install pi on the host

```bash
ssh $TARGET_HOST sudo /opt/hetzbot/skills/infra/pi/install.sh
```

Idempotent. Ensures node is installed first (delegates to the runtime
skill). `npm install -g @mariozechner/pi-coding-agent` runs under
`/etc/npmrc` lockdown — no arbitrary postinstall execution.

### 4. Propagate the key to `/etc/hetzbot/pi.env`

The bash below expands `$MINIMAX_API_KEY` **in the operator's shell**
(outside the LLM's context) and pipes it straight into ssh stdin.
The key is never materialized for the agent and never written to any
local file.

```bash
ssh $TARGET_HOST "sudo install -d -m 0700 /etc/hetzbot && \
  sudo tee /etc/hetzbot/pi.env >/dev/null && \
  sudo chmod 0600 /etc/hetzbot/pi.env && \
  sudo chown root:root /etc/hetzbot/pi.env" <<EOF
MINIMAX_API_KEY=$MINIMAX_API_KEY
EOF
```

Verify perms (safe — doesn't print the content):

```bash
ssh $TARGET_HOST 'sudo stat -c "%a %U:%G %n" /etc/hetzbot/pi.env'
# Expected: 600 root:root /etc/hetzbot/pi.env
```

### 5. Verify pi can auth (without echoing the key)

```bash
ssh $TARGET_HOST 'set -a; . /etc/hetzbot/pi.env; set +a; pi --version'
```

Expected: pi prints its version. If it fails complaining about
missing credentials, the env var name doesn't match what pi expects —
Minimax uses `MINIMAX_API_KEY` exactly; other providers: check the
upstream docs.

### 6. Report

Tell the user:

> pi installed on `$TARGET_HOST`, default provider Minimax.
> Interactive use:
> `ssh $TARGET_HOST` then `set -a; . /etc/hetzbot/pi.env; set +a; pi`.
> Programmatic use: add `EnvironmentFile=/etc/hetzbot/pi.env` to any
> systemd unit that needs pi.

## Rotating the key

The operator updates `MINIMAX_API_KEY` in whichever file they used,
re-sources it, then re-runs step 4. `/etc/hetzbot/pi.env` is
overwritten; no service restart needed unless a consumer caches the
key.

## Security

- pi runs shell commands and edits files by design — treat invoking
  pi as shell access for whatever user runs it.
- `/etc/hetzbot/pi.env` is `0600 root:root`. Systemd service units
  that need pi read it via `EnvironmentFile=`; each service's
  90-hardening drop-in keeps the blast radius small.
- Per-host opt-in. Hosts without pi are unaffected.
- The operator's secret file is gitignored (for `.env`) or outside
  the repo (for `~/.config/hetzbot/keys.env`). Never committed.

## Review behavior

`review.sh` emits:
- `OK` with version if pi is installed.
- Silent if pi is absent (it's optional).
- `HIGH` if `/etc/hetzbot/pi.env` exists with wrong permissions
  (expected `0600 root:root`).
- `MEDIUM` if another binary named `pi` is on PATH but it isn't the
  pi.dev coding agent.

## Uninstall

```bash
ssh $TARGET_HOST 'sudo npm uninstall -g @mariozechner/pi-coding-agent && \
                  sudo rm -f /etc/hetzbot/pi.env'
```

Leaves node in place — other skills may depend on it.
