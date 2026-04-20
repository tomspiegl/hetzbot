---
name: hetzbot-add-host
description: Add a new Hetzner Cloud host to the fleet. Triggers: user says "add a host", "new server", "provision a box". Program-style — asks the user for inputs, edits hosts.tfvars, runs `tofu apply`, bootstraps via SSH, then joins Tailscale.
---

# add-host

Adds one Hetzner Cloud VM to the fleet. Bootstrap access is via SSH
from the operator's public IP; once Tailscale joins, SSH access is
removed and all further access goes over the tailnet. Typical elapsed
time: ~5 minutes. Interactive — do not skip prompts.

## Program

```python
# 1. Gather inputs.

host_name = ask("Host name? (short, e.g. hetz-1)")
if not re.match(r"^[a-z0-9-]{1,30}$", host_name):
    reject("lowercase letters, digits, - only; max 30 chars")
if host_name in hosts_tfvars:
    reject("already defined in hosts.tfvars")

location = ask(
    "Hetzner location?",
    choices=["nbg1", "fsn1", "hel1", "ash", "hil"],
    default="nbg1",
)

server_type = ask(
    "Server type?",
    choices=["cpx22", "cpx32", "cpx42", "cax11", "cax21", "ccx13"],
)
# cpx22 = x86 4GB, cpx32 = x86 8GB, cpx42 = x86 16GB
# cax11 = ARM 4GB, cax21 = ARM 8GB, ccx13 = dedicated 8GB

public = ask(
    "Serves HTTPS on 443?",
    choices=["yes", "no"],
    default="no",
)
if public == "yes" and not env.DOMAIN:
    fail("PUBLIC=yes requires DOMAIN in .env; set it and retry")

backups = ask(
    "Enable weekly Hetzner Backups? (+20% server cost)",
    choices=["yes", "no"],
    default="yes",
)

# 2. Edit hosts.tfvars.

edit("hosts.tfvars", append_under="hosts = { ... }", block=f'''
{host_name} = {{
  location = "{location}"
  type     = "{server_type}"
  public   = {public}
  backups  = {backups}
  services = []
}}
''')

show_diff()
if ask("Apply this edit?", choices=["yes", "no"]) != "yes":
    revert("hosts.tfvars")
    fail("aborted by user")

# 3. Detect operator IP and select SSH key.

operator_ip = run("curl -sf https://ifconfig.me").stdout.strip()
inform(f"Operator public IP: {operator_ip}")

# Find ed25519 public keys in ~/.ssh
pub_keys = glob("~/.ssh/*.pub")
ed25519_keys = [k for k in pub_keys if "ed25519" in k]

if not ed25519_keys:
    inform("""No ed25519 SSH key found. Create one:
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_hetzner -C "your@email"
  (passphrase is optional but recommended)""")
    fail("create an SSH key and retry")

# Prefer a key with "hetzner" in the name; otherwise ask
hetzner_keys = [k for k in ed25519_keys if "hetzner" in k]
if len(hetzner_keys) == 1:
    ssh_pub_path = hetzner_keys[0]
    inform(f"Using SSH key: {ssh_pub_path}")
elif len(ed25519_keys) == 1:
    ssh_pub_path = ed25519_keys[0]
    inform(f"Using SSH key: {ssh_pub_path}")
else:
    ssh_pub_path = ask(f"Multiple SSH keys found. Which one?", choices=ed25519_keys)

ssh_key_id = ensure_ssh_key_uploaded(ssh_pub_path)
# ensure_ssh_key_uploaded:
#   1. Read the chosen .pub file
#   2. Check if already in Hetzner project via GET /v1/ssh_keys
#   3. If not, upload via POST /v1/ssh_keys
#   4. Return the Hetzner SSH key ID

# 4. Get a Tailscale auth key (operator action — agent cannot).

inform("""Generate a Tailscale auth key:
  1. Open https://login.tailscale.com/admin/settings/keys
  2. Create key: single-use, 1h expiry, tag 'tag:host'.
  3. Paste into .env as TAILSCALE_AUTHKEY=tskey-... and save.""")

while not env.TAILSCALE_AUTHKEY or not env.TAILSCALE_AUTHKEY.startswith("tskey-"):
    if ask("Auth key set in .env?", choices=["retry", "abort"]) == "abort":
        fail("no Tailscale auth key")
    reload_env()

# 5. Apply tofu with operator_ip and ssh_keys for bootstrap access.

run(f"tofu -chdir=tofu plan -var='operator_ip={operator_ip}' -var='ssh_keys=[{ssh_key_id}]'")
show_plan()
if ask("Proceed with apply? (creates billable resources)", choices=["yes", "no"]) != "yes":
    fail("aborted by user")

if run(f"tofu -chdir=tofu apply -var='operator_ip={operator_ip}' -var='ssh_keys=[{ssh_key_id}]'").exit_code != 0:
    fail("tofu apply failed — see Recovery below; do NOT retry blindly")

server_ip = run("tofu -chdir=tofu output -json hosts").json[host_name]["ipv4"]

# 6. Wait for SSH on public IP (cloud-init takes ~2-4 min).

waited = 0
while True:
    if run(f"ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@{server_ip} echo ok").exit_code == 0:
        break
    if waited >= 600:
        fail("SSH not reachable after 10 min")
    sleep(15)
    waited += 15
    if waited % 60 == 0:
        inform(f"waiting for SSH... {waited}s")

# 7. Verify cloud-init completed and Tailscale joined.

run(f"ssh root@{server_ip} 'cloud-init status --wait'")
run(f"ssh root@{server_ip} 'tailscale status'")

if host_name not in tailscale_online_peers():
    # Tailscale didn't join — debug via SSH.
    inform("Tailscale not on tailnet. Checking logs...")
    run(f"ssh root@{server_ip} 'journalctl -u tailscaled --no-pager | tail -20'")
    fail("Tailscale join failed — check logs above")

# 8. Verify SSH over tailnet.

for attempt in range(1, 6):
    if run(f"ssh -o ConnectTimeout=5 {host_name} uptime").exit_code == 0:
        break
    sleep(10)
else:
    fail(f"can't SSH {host_name} over Tailscale after 5 attempts")

# 9. Remove bootstrap SSH access — clear operator_ip only.
# ssh_keys is in ignore_changes so it won't force server replacement,
# but we only need to remove the firewall rule anyway.

inform("Tailscale working. Removing bootstrap SSH access...")
run("tofu -chdir=tofu apply -var='operator_ip='")
# This removes the port-22 rule from the Hetzner firewall.
# The SSH key on the server is harmless — the firewall blocks 22.
# UFW rule stays but is unreachable through the firewall.

# 10. Run the reviewer.

exit_code = run(f"bash $HETZBOT_ROOT/skills/hetzner/review-host/review.sh {host_name}").exit_code
if exit_code == 2:    # CRITICAL
    warn("reviewer reports CRITICAL — halt. Do not add services.")
    fail()
elif exit_code == 1:  # HIGH
    warn("reviewer reports HIGH findings — continue with caveat")

# 11. Done.

inform(f"""Host {host_name} is online and on the tailnet.
Bootstrap SSH access has been removed.
Next: invoke the add-service skill to attach a service, then deploy
with: bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh {host_name}""")
```

## Recovery

**`tofu apply` failed mid-flight.**
Inspect with `tofu -chdir=tofu state list` + `tofu -chdir=tofu plan`.
If a partial resource exists, fix the underlying cause and re-apply,
or `tofu destroy -target=<resource>` the orphan first.

**SSH reachable but Tailscale didn't join.**
Common causes: auth key expired (1h TTL) / wrong tag / clock skew /
Tailscale control-plane outage.
1. SSH in: `ssh root@<server_ip>` (while bootstrap SSH is still open).
2. `journalctl -u cloud-final` and `journalctl -u tailscaled`.
3. If the auth key expired: generate a fresh one, then on the server
   run `tailscale up --authkey=tskey-... --ssh --hostname=<host>`.

**Host reachable but `review-host` reports CRITICAL.**
Do **not** add services. Resolve the finding first.

**Re-entrancy after a crashed session.**
Resume by checking in order:
1. Is `$HOST_NAME` in `hosts.tfvars`? (step 2 done)
2. Can you SSH to the public IP? (step 6 done)
3. Is it a Tailscale peer? (step 7 done)
4. Has bootstrap SSH been removed? (step 9 done)
5. Does the reviewer pass? (step 10 done)
Resume at the first check that fails.

## Rules

- **No invented defaults for `HOST_NAME`.** Re-ask on empty.
- **`.env` is session-local.** Never commit `TAILSCALE_AUTHKEY`.
- **Confirm before every `tofu apply`.** It creates billable resources.
- **Remove bootstrap SSH after Tailscale join.** Don't leave port 22 open.
