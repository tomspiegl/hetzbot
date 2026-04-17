---
name: hetzbot-restore
description: Restore a service's DB + /srv files from restic. Triggers: user says "restore <service>", "roll back <service> data", "recover <service>". Program-style. Stops the service, fetches snapshot, restores, restarts.
---

# restore

Interactive recovery workflow. Targets a single service — not the
whole host. For "rebuild the whole host from scratch", see the
architecture doc's recovery section.

## Program

```python
# 1. Identify.

host_name = ask("Host?", choices=list(hosts_tfvars.keys()))

service_name = ask(
    "Service to restore?",
    choices=hosts_tfvars[host_name].services,
)
if service_name not in hosts_tfvars[host_name].services:
    reject("service not assigned to this host; add-service first if "
           "this is a fresh host rebuild")

# 2. Pick a snapshot.

snapshots = run(f"ssh {host_name} 'sudo restic snapshots --tag hetzbot "
                f"--host {host_name} --last 10'").stdout
show(snapshots)

snapshot_id = ask(
    "Snapshot to restore from? (short ID or 'latest')",
    default="latest",
)

# For the per-DB dump we want the matching date:
if snapshot_id == "latest":
    dump_date = today()
else:
    dump_date = snapshot_date_from_restic_json(snapshot_id)

# 3. Safety checkpoint — current state before we overwrite.

inform(f"About to restore {service_name} from {snapshot_id}. "
       "The current state will be overwritten. Proceed?")
if ask("Proceed?", choices=["yes", "no"]) != "yes":
    fail()

# Snapshot the current state to a side location just in case.
ssh_run(host_name, f'''sudo bash -c "
  cp -a /srv/{service_name} /srv/{service_name}.pre-restore-$(date +%s)
  docker exec postgres pg_dump -U postgres -Fc {service_name} \
    > /var/backups/pg/{service_name}-pre-restore-$(date +%s).dump
"''')

# 4. Stop the service.

ssh_run(host_name, f"sudo systemctl stop {service_name}")

# 5. Restore files from restic.

ssh_run(host_name, f'''sudo bash -c "
  set -a; . /etc/hetzbot/restic.env; set +a
  restic restore {snapshot_id} --target / --include /srv/{service_name}
  restic restore {snapshot_id} --target / --include /var/backups/pg/{service_name}-{dump_date}.dump
"''')

# 6. Restore the database from the pg_dump.

ssh_run(host_name, f'''sudo bash -c "
  dump=/var/backups/pg/{service_name}-{dump_date}.dump
  [ -f \\$dump ] || {{ echo no dump found for {service_name} on {dump_date}; exit 1; }}

  # Drop + recreate, then pg_restore.
  docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS \\"{service_name}\\" WITH (FORCE);
CREATE DATABASE \\"{service_name}\\" OWNER \\"{service_name}\\";
SQL
  docker exec -i postgres pg_restore -U postgres -d {service_name} --clean --if-exists < \\$dump
"''')

# 7. Restart + verify.

ssh_run(host_name, f"sudo systemctl start {service_name}")

state = None
for attempt in range(6):
    state = run(f"ssh {host_name} systemctl is-active {service_name}").stdout.strip()
    if state == "active":
        break
    sleep(5)

if state != "active":
    fail(f"service did not come back up; check: ssh {host_name} journalctl -u {service_name} -n 100. "
         f"The pre-restore copies at /srv/{service_name}.pre-restore-* and "
         f"/var/backups/pg/{service_name}-pre-restore-*.dump are your rollback.")

run(f"bash $HETZBOT_ROOT/skills/hetzner/review-host/review.sh {host_name}")

inform(f"""{service_name} restored from {snapshot_id}.
Pre-restore backups kept at:
  /srv/{service_name}.pre-restore-<ts>
  /var/backups/pg/{service_name}-pre-restore-<ts>.dump
Delete those once the restore is proven good.""")
```

## Rules

- **Pre-restore backup is non-optional.** The script above creates it
  automatically. Don't skip — a restore from the wrong snapshot is
  recoverable if you still have the pre-restore copy.
- **Stop before restore, not during.** The service holding the DB
  open will conflict with the `DROP DATABASE`.
- **Verify with the review-host script.** A successful restart isn't
  proof the data came back correctly. Run
  `bash $HETZBOT_ROOT/skills/hetzner/review-host/review.sh $HOST_NAME`
  to at least confirm basic health, then manually verify the service's
  own internals.

## What this skill does NOT do

- Does not restore the service's code — code lives in the GitHub repo,
  not in restic. Re-run `bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh <host>` to get latest code.
- Does not restore `/etc/hetzbot/*` or Docker volumes. Those are part
  of the host-wide rebuild, not a per-service restore.
