---
name: hetzbot-rotate-service
description: Rotate a service's Postgres password. Triggers: user says "rotate <service>", "rotate <service>'s password", "rotate db creds for <service>". Issues ALTER ROLE, rewrites /srv/<svc>/.env, restarts the unit. Program-style — the unit bounces, so callers should be ready for a brief blip.
---

# rotate-service

Rotates one service's Postgres password on one host. Idempotent —
safe to re-run. Causes a brief service restart (seconds).

Underlying mechanism: `skills/infra/postgres/rotate.sh` on the host.
`ALTER ROLE ... PASSWORD '...'`, rewrite the `DATABASE_URL` line in
`/srv/<svc>/.env` (preserving other keys), then `systemctl restart
<svc>`.

## Program

```python
# 1. Identify.

host_name = ask("Host?", choices=list(hosts_tfvars.keys()))

service_name = ask(
    "Service to rotate?",
    choices=hosts_tfvars[host_name].services,
)

# 2. Pre-flight — confirm current state.

if run(f"ssh {host_name} test -f /srv/{service_name}/.env").exit_code != 0:
    fail(f"{service_name} not provisioned on {host_name} (/srv/{service_name}/.env missing)")

was_active = run(f"ssh {host_name} systemctl is-active {service_name}").exit_code == 0
# Scheduled (timer-only) services won't be "active"; that's fine —
# rotation still applies. was_active just informs the post-check.

# 3. Confirm (rotation bounces the unit).

inform(f"""About to rotate {service_name} on {host_name}:
  - ALTER ROLE {service_name} in Postgres (new 32-hex password)
  - Rewrite DATABASE_URL in /srv/{service_name}/.env
  - systemctl restart {service_name} (brief outage)
Any client holding the old password will fail after the ALTER.""")

if ask("Proceed?", choices=["yes", "no"]) != "yes":
    fail("aborted by user")

# 4. Rotate.

if run(f"ssh {host_name} sudo /opt/hetzbot/skills/infra/postgres/rotate.sh {service_name}").exit_code != 0:
    fail(
        "rotate.sh failed — inspect the output. Common causes: "
        "Postgres container not running, service user not found, "
        f"/srv/{service_name}/.env not writable. See Recovery."
    )

# 5. Post-check.

if was_active:
    state = run(f"ssh {host_name} systemctl is-active {service_name}").stdout.strip()
    if state != "active":
        warn(f"unit not active after rotation — check "
             f"'journalctl -u {service_name} -n 100' for auth errors")
        fail()

inform(f"{service_name} on {host_name} rotated.")
```

## Recovery

**`rotate.sh` failed before the ALTER ROLE ran.**
The old password still works. Re-run after fixing the underlying
issue (Postgres down, sudo rights, etc.).

**`rotate.sh` failed after ALTER ROLE but before rewriting `.env`.**
The service will fail to reconnect on next restart (old password in
`.env`, new one in DB). Re-running `rotate.sh` is safe — it generates
a fresh password and rewrites `.env` atomically; the prior ALTER is
overridden.

**Unit won't come back up.**
1. `ssh $HOST_NAME journalctl -u $SERVICE_NAME -n 100` — look for
   `password authentication failed` (rewrite didn't land) or
   `FATAL: role "$SERVICE_NAME" does not exist` (DB out of sync).
2. If the role is missing: the service was never provisioned here —
   this skill is the wrong tool; use add-service.
3. If `.env` looks wrong: re-run the rotate script — it's idempotent.

## Rules

- **One service at a time.** No bulk rotation — each restart is a
  user-visible blip; let the operator decide the cadence.
- **Don't rotate during a deploy.** The deploy script reads `.env`;
  a mid-flight rotation can race. Wait for `deploy.sh` to exit.
- **Do not copy, print, or log the new password.** `rotate.sh` writes
  it directly to `/srv/<svc>/.env` on the host. It never leaves the
  host; not in the agent's context, not in the operator's shell.
