---
name: hetzbot-deploy
description: Deploy the current fleet state to a host (rsync skills + services, install needed infra/runtimes, clone/build/start services). Triggers: user says "deploy", "push changes", "roll out". Runs `skills/ops/deploy/deploy.sh`.
---

# Deploy

Use when the user has changed `services/` or `hosts.tfvars` and wants the host to match.

## When to use

- After editing a service's `source` (code change, new SHA pin).
- After changing a service's `.service` / `.env.example` / `caddy.conf`.
- After adding a service to a host's `services` list in `hosts.tfvars`.
- After adding a host (sequence: apply the fleet's tofu config (`tofu apply`) then `bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh <host>`).

## Steps

1. Confirm the operator has `HCLOUD_TOKEN` + `AWS_*` creds in `.env` (otherwise `tofu output` fails).
2. Run `bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh <host> --dry-run` first to preview rsync + SSH commands.
3. Run `bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh <host>`.
4. On success, verify:
   ```
   ssh <host> systemctl list-units --failed
   ssh <host> journalctl -u <service> -n 30
   ```
5. If a public host, the Caddyfile is reassembled and validated before reload. A broken `caddy.conf` snippet fails the deploy rather than breaking the running Caddy.

## Rollback

Two paths:

- **Declarative (preferred):** edit `services/<name>/source` to pin a previous SHA, `bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh <host>`.
- **Imperative (emergency):** `ssh <host>` and `git -C /srv/<name>/repo checkout <sha> && bash /srv/<name>/build.sh && systemctl restart <name>`.

## Notes

- Deploy is idempotent. Running it with no changes re-pulls and restarts; safe but noisy.
- `--dry-run` prints every rsync and SSH command without executing.
