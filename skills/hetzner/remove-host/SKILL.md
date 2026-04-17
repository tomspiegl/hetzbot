---
name: hetzbot-remove-host
description: Safely destroy a Hetzner Cloud host and remove it from the fleet. Triggers: user says "remove <host>", "decommission <host>", "destroy <host>". Program-style, confirms repeatedly — destructive.
---

# remove-host

Interactive destructive workflow. Removes the VM, cleans up local
state, and reminds the operator about Tailscale device cleanup.

## Program

```python
# 1. Identify and validate.

host_name = ask("Host to remove?", choices=list(hosts_tfvars.keys()))
if host_name not in hosts_tfvars:
    reject("not in hosts.tfvars")

services = hosts_tfvars[host_name].services

# 2. Guardrails.

if len(services) > 0:
    warn(f"This host has {len(services)} services assigned: {services}")
    strategy = ask(
        "Remove each service from the host (recommended) or force-destroy?",
        choices=["remove-first", "force"],
    )
    if strategy == "remove-first":
        for svc in services:
            run_skill("ops/remove-service", service=svc, host=host_name)
            # (Exits this skill while remove-service runs, then comes back.)
        services = hosts_tfvars[host_name].services  # should now be empty

# 3. Final backup.

if ask("Force one last backup before destroy? (recommended)",
       choices=["yes", "no"], default="yes") == "yes":
    if run(f"ssh {host_name} sudo /opt/hetzbot/skills/ops/deploy/backup-now.sh").exit_code != 0:
        if ask("Backup failed. Continue with destroy anyway?",
               choices=["yes", "no"]) != "yes":
            fail()

# 4. Confirm three times (destructive).

inform(f"""About to destroy:
  - Hetzner Cloud server: {host_name}
  - Firewall: fw-{host_name}
  - DNS A/AAAA records (if public)
  - All data on the VM's disk (NOT restic snapshots — those survive)
Restic snapshots remain in Object Storage; `restic restore` works
from any future host as long as RESTIC_PASSWORD is kept.""")

if ask(f"Type the host name to confirm:") != host_name:
    fail("not confirmed")

if ask("Really? (type YES in caps)") != "YES":
    fail("not confirmed")

# 5. Destroy infrastructure (tofu).

if run(f'''tofu -chdir=tofu destroy -auto-approve \
    -target='module.host["{host_name}"]' \
    -var-file=../hosts.tfvars \
    ...all other vars...''').exit_code != 0:
    fail("tofu destroy failed — inspect state with 'tofu state list'")

# 6. Remove the entry from hosts.tfvars.

edit("hosts.tfvars", remove_key=f"hosts.{host_name}")
show_diff()
if ask("Apply?", choices=["yes", "no"]) != "yes":
    revert("hosts.tfvars")

# 7. Reminders (things the agent cannot automate).

inform(f"""Done. Remaining manual cleanup:
  1. Tailscale admin → Machines → remove '{host_name}' from the
     tailnet (otherwise the MagicDNS name keeps resolving to a
     dead IP for a while).
  2. If this host had a public domain, DNS records were already
     removed by tofu. External caches may linger — verify with
     `dig {host_name}.$DOMAIN`.
  3. Commit hosts.tfvars change + push.""")
```

## Rules

- **Two confirmations minimum.** `tofu destroy` on a production host
  is irreversible once the disk is gone.
- **Don't skip the backup step** unless the host is already provably
  dead. The backup is cheap; the safety it buys is not.
- **Tailscale device cleanup is manual** — there's no API we trust to
  run without the operator watching.
- **If `tofu destroy` fails halfway**, run `tofu state list` to see
  what remains. Don't edit `hosts.tfvars` until state matches reality.

## What this skill does NOT do

- It does not delete the restic snapshots. Those are retained per the
  forget-policy and can be restored to a new host.
- It does not delete the Object Storage bucket. That would orphan the
  tofu state for other fleets.
- It does not delete the Hetzner project / account.
