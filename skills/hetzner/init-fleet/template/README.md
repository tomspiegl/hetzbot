# {{FLEET_NAME}}

Fleet repo — Hetzner Cloud hosts + first-party services. Consumed by
the [hetzbot](https://github.com/tomspiegl/hetzbot) framework, which is
expected to live at `$HETZBOT_ROOT` (see `.env`).

## Layout

| Path | What |
|---|---|
| `hosts.tfvars` | Fleet definition. Edited by the `add-host` skill. |
| `services/<name>/` | First-party service manifests. |
| `.env` | Session credentials (gitignored). |
| `justfile` | Thin wrapper that delegates to hetzbot's justfile. |

## Quick start

```bash
cp .env.example .env                # fill from your personal vault
just init                           # one-time: tofu backend init
just plan                           # preview before any apply
```

Add hosts and services via hetzbot's skills (run the agent from this
directory; it reads `CLAUDE.md` in the hetzbot repo).

## Upgrading hetzbot

```bash
git -C $HETZBOT_ROOT pull --ff-only   # track main
# or
git -C $HETZBOT_ROOT checkout <tag>   # pin a version
```
