---
name: hetzbot-snapshot-host
description: Take a manual Hetzner Cloud whole-disk snapshot of a host. Triggers: user says "snapshot hetz-1", "take a snapshot before the upgrade", "create a rollback image". Complements the weekly automatic Backups and the restic data-recovery path.
---

# snapshot-host

Creates a Hetzner Cloud **snapshot** of one host on demand. Snapshots
are separate from Hetzner automatic **Backups** (the `backups = true`
flag in `hosts.tfvars` — those are weekly, 7-day retention). Snapshots
are manual, stored indefinitely, and billed per GB-month.

Use this **before** any risky operation on a live host:
- Upgrading a shared infra skill (Postgres major version bump).
- Applying a `user-data.yaml.tpl` change that requires a destroy/recreate.
- Running a migration that mutates `/srv/<svc>/` in place.
- Any time you want a "yesterday's box" rollback option.

## Program

```python
# 1. Identify.

host_name = ask("Host to snapshot?", choices=list(tofu_output.hosts.keys()))

hcloud_id = tofu_output.hosts[host_name].hcloud_id
if not hcloud_id:
    fail("no hcloud_id in tofu output — run `tofu apply` to refresh")

description = ask(
    "Snapshot description? (becomes the image label; max 100 chars)",
    default=f"hetzbot/{host_name}/pre-change-{now('%FT%H%M')}",
)

# 2. Sanity.

if not env.HCLOUD_TOKEN:
    fail("HCLOUD_TOKEN not set in .env")

# Optional but recommended — flush Postgres + file system to disk
# before snapshotting, so the image captures a consistent state.
if ask("Quiesce the host first (sync + pg_dump before snapshot)?",
       choices=["yes", "no"], default="yes") == "yes":
    run(f"ssh {host_name} sudo sync")
    run(f"ssh {host_name} sudo /opt/hetzbot/skills/infra/postgres/backup.sh")
    # writes per-DB pg_dump files to /var/backups/pg/ before the
    # snapshot captures the disk.

# 3. Create the snapshot via Hetzner API.

response = run(f'''curl -sS -X POST \
    "https://api.hetzner.cloud/v1/servers/{hcloud_id}/actions/create_image" \
    -H "Authorization: Bearer $HCLOUD_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{{"type":"snapshot","description":"{description}","labels":{{"managed_by":"hetzbot","host":"{host_name}"}}}}' ''').stdout

action_id = json.loads(response)["action"]["id"]
image_id  = json.loads(response)["image"]["id"]
status    = json.loads(response)["action"]["status"]

# 4. Poll until the action finishes.

waited = 0
while status != "success":
    if status == "error":
        fail(f"snapshot action failed: {json.loads(response)['action']['error']}")
    if waited > 1800:  # 30 min cap; huge disks may take longer
        warn(f"snapshot still running at {waited}s — continuing in background")
        break
    sleep(10)
    waited += 10

    response = run(f'''curl -sS \
        "https://api.hetzner.cloud/v1/actions/{action_id}" \
        -H "Authorization: Bearer $HCLOUD_TOKEN" ''').stdout
    status = json.loads(response)["action"]["status"]

# 5. Report.

inform(f"""Snapshot created for {host_name}.
  image_id:    {image_id}
  description: {description}

List snapshots for this host:
  curl -sS 'https://api.hetzner.cloud/v1/images?type=snapshot&label_selector=host={host_name}' \\
    -H 'Authorization: Bearer $HCLOUD_TOKEN' | jq '.images[] | {{id, description, created}}'

To roll back to this snapshot: rebuild the host from this image_id.
This is destructive — see Recovery below.""")
```

## Recovery — rolling back to a snapshot

**Rebuilding from a snapshot** replaces the current disk entirely.
Any data created after the snapshot is lost (unless restic has it).
Use only when the current host is broken beyond normal repair.

Steps (Hetzner web console or hcloud CLI):

1. Stop services on the host first to prevent split-brain once the
   rollback boots:
   ```
   ssh $HOST_NAME 'sudo systemctl stop hetzbot-backup.timer && \
                   for u in $(ls /etc/systemd/system/*.service 2>/dev/null); do \
                     sudo systemctl stop $(basename $u .service); \
                   done'
   ```
2. Web console: **Server → Rebuild → select the snapshot image**.
   Or via API:
   ```
   curl -X POST "https://api.hetzner.cloud/v1/servers/$hcloud_id/actions/rebuild" \
     -H "Authorization: Bearer $HCLOUD_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"image":"$image_id"}'
   ```
3. Wait for reboot. Tailscale will rejoin automatically if the
   snapshot was taken after the tailnet join (it almost always is —
   snapshots are only useful after bootstrap).
4. Verify via the review-host script.

## Deletion / retention

Snapshots persist forever until deleted. Clean up old ones to control
cost:

```
curl -sS "https://api.hetzner.cloud/v1/images?type=snapshot&label_selector=managed_by=hetzbot" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  | jq '.images[] | select(.created < "<ISO date>") | .id' \
  | xargs -I{} curl -X DELETE "https://api.hetzner.cloud/v1/images/{}" \
      -H "Authorization: Bearer $HCLOUD_TOKEN"
```

No automatic prune — snapshots are deliberate; losing them silently
defeats the point.

## Rules

- **Quiesce before snapshotting stateful services.** An inconsistent
  disk image of a running Postgres is recoverable but annoying; a
  pre-snapshot `pg_dump` gives you a clean restore path.
- **Don't rely on snapshots alone for recovery.** They're
  Hetzner-internal — if the account is compromised or the region has
  an outage, restic (off-provider, client-side encrypted) is what
  keeps you recoverable.
- **Label snapshots via `labels.host` and `labels.managed_by`** so
  cleanup queries can find them programmatically.
