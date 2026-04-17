---
name: hetzbot-remove-service
description: Safely remove a first-party service from a host. Triggers: user says "remove <service>", "decommission <service>", "tear down <service>". Stops the unit, drops the DB, removes /srv, unassigns from host. Program-style with confirmations.
---

# remove-service

Interactive destructive workflow. Cleans a service off exactly one
host without touching others. Uses `remove.sh` on the host for the
mechanical steps.

## Program

```python
# 1. Identify.

host_name = ask("Host?", choices=list(hosts_tfvars.keys()))

service_name = ask(
    "Service to remove?",
    choices=hosts_tfvars[host_name].services,
)
if service_name not in hosts_tfvars[host_name].services:
    reject()

# 2. Backup.

if ask("Force a backup of this service's DB before removal?",
       choices=["yes", "no"], default="yes") == "yes":
    run(f"ssh {host_name} 'sudo /opt/hetzbot/skills/infra/postgres/backup.sh'")
    run(f"ssh {host_name} sudo /opt/hetzbot/skills/ops/deploy/backup-now.sh")  # one more restic pass

# 3. Confirm.

inform(f"""About to remove {service_name} from {host_name}:
  - Stop + disable systemd unit + timer
  - Drop Postgres database + role
  - Remove /srv/{service_name} (code, .env, any data written there)
  - Remove the service user
  - Remove services/{service_name}/caddy.conf if present + rebuild Caddyfile
  - Drop {service_name} from hosts.tfvars[{host_name}].services

Restic snapshots of /srv/{service_name} keep their retention. Drop
them manually with 'restic forget --tag {service_name}' if you want
a full purge.""")

if ask("Type the service name to confirm:") != service_name:
    fail("not confirmed")

# 4. Run the mechanical cleanup on the host.

if run(f"ssh {host_name} 'sudo /opt/hetzbot/skills/ops/remove-service/remove.sh {service_name}'").exit_code != 0:
    fail("remove.sh failed mid-flight — inspect and resume manually")

# 5. Update the fleet state + re-sync.

edit("hosts.tfvars", remove_from_list=f"hosts.{host_name}.services", value=service_name)
show_diff()
ask("Apply?", choices=["yes", "no"])

run(f"rm -rf services/{service_name}")  # local manifest gone
show_diff()
ask("Apply?", choices=["yes", "no"])

if hosts_tfvars[host_name].public and path_exists(f"services/{service_name}/caddy.conf"):
    run(f"bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh {host_name}")
    # triggers caddy reassemble + reload

# 6. Review.

run(f"bash $HETZBOT_ROOT/skills/hetzner/review-host/review.sh {host_name}")
# Expect no findings about {service_name} anymore.

inform(f"""{service_name} removed from {host_name}.
To permanently delete restic snapshots tagged with this service
(not recommended immediately — keeps recovery option for ~1 month):
  ssh {host_name} sudo restic forget --tag {service_name} --prune""")
```

## Rules

- **Always back up first.** A service's data is often restorable, but
  "we can recover from restic" is a hope without a recent snapshot.
- **Caddy reassemble only on public hosts.** For headless hosts, skip
  step 5's deploy — the remove.sh on host already handles local state.
