---
name: hetzbot-add-host
description: Add a new Hetzner Cloud host to the fleet. Triggers: user says "add a host", "new server", "provision a box". Program-style — asks the user for inputs, edits hosts.tfvars, runs `tofu apply`, waits for Tailscale join.
---

# add-host

Adds one Hetzner Cloud VM to the fleet and waits for it to come up on
Tailscale. Typical elapsed time: ~3 minutes. Interactive — do not
skip prompts.

## Program

```python
# 1. Gather inputs.

host_name = ask("Host name? (short, e.g. hetz-1)")
if not re.match(r"^[a-z0-9-]{1,30}$", host_name):
    reject("lowercase letters, digits, - only; max 30 chars")
if host_name in hosts_tfvars:
    reject("already defined in hosts.tfvars")
# No invented default. Re-ask on empty.

location = ask(
    "Hetzner location?",
    choices=["nbg1", "fsn1", "hel1", "ash", "hil"],
    default="nbg1",
)

server_type = ask(
    "Server type?",
    choices=["cx22", "cx32", "cx42", "ccx13"],
)
# cx22 = 4GB (default), cx32 = 8GB, cx42 = 16GB, ccx13 = dedicated vCPU

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

# 3. Get a Tailscale auth key (operator action — agent cannot).

inform("""Generate a Tailscale auth key:
  1. Open https://login.tailscale.com/admin/settings/keys
  2. Create key: single-use, 1h expiry, tag 'tag:host'.
  3. Paste into .env as TAILSCALE_AUTHKEY=tskey-... and save.""")

while not env.TAILSCALE_AUTHKEY or not env.TAILSCALE_AUTHKEY.startswith("tskey-"):
    if ask("Auth key set in .env?", choices=["retry", "abort"]) == "abort":
        fail("no Tailscale auth key")
    reload_env()

# 4. Apply tofu.

run("tofu -chdir=tofu plan")
show_plan()
if ask("Proceed with apply? (creates billable resources)", choices=["yes", "no"]) != "yes":
    fail("aborted by user")

if run("tofu -chdir=tofu apply").exit_code != 0:
    fail("tofu apply failed — see Recovery below; do NOT retry blindly")

# 5. Wait for Tailscale join (cloud-init takes ~90-180s).

waited = 0
while True:
    if host_name in tailscale_online_peers():
        break
    if waited >= 600:
        fail("not on tailnet after 10 min — check Hetzner console (see Recovery)")
    sleep(15)
    waited += 15
    if waited % 60 == 0:
        inform(f"still waiting... {waited}s")

# 6. Verify SSH over tailnet.

for attempt in range(1, 6):
    if run(f"ssh -o ConnectTimeout=5 {host_name} uptime").exit_code == 0:
        break
    sleep(10)
else:
    fail(f"can't SSH {host_name} over Tailscale after 5 attempts")

# 7. Run the reviewer.

exit_code = run(f"bash $HETZBOT_ROOT/skills/hetzner/review-host/review.sh {host_name}").exit_code
if exit_code == 2:    # CRITICAL
    warn("reviewer reports CRITICAL — halt. Do not add services.")
    fail()
elif exit_code == 1:  # HIGH
    warn("reviewer reports HIGH findings — continue with caveat")

# 8. Done.

inform(f"""Host {host_name} is online and on the tailnet.
Next: invoke the add-service skill to attach a service, then deploy
with: bash $HETZBOT_ROOT/skills/ops/deploy/deploy.sh {host_name}""")
```

## Recovery

**`tofu apply` failed mid-flight.**
Inspect with `tofu -chdir=tofu state list` + `tofu -chdir=tofu plan`.
If a partial resource exists, fix the underlying cause and re-apply,
or `tofu destroy -target=<resource>` the orphan first.

**Tailscale join didn't happen.**
Common causes: auth key expired (1h TTL) / clock skew / Tailscale
control-plane outage.
1. Open the Hetzner web console; log in as `root` with `CONSOLE_ROOT_PASSWORD`.
2. `journalctl -u cloud-final` and `journalctl -u tailscaled`.
3. If the auth key expired: generate a fresh one, put it in `.env`,
   then via the console run `tailscale up --authkey=tskey-... --ssh`.

**Host reachable but `review-host` reports CRITICAL.**
Do **not** add services. Resolve the finding first.

**Re-entrancy after a crashed session.**
Resume by checking in order:
1. Is `$HOST_NAME` in `hosts.tfvars`? (step 2 done)
2. Is it a Tailscale peer? (steps 4–5 done)
3. Does the reviewer pass? (step 7 done)
Resume at the first check that fails.

## Rules

- **No invented defaults for `HOST_NAME`.** Re-ask on empty.
- **`.env` is session-local.** Never commit `TAILSCALE_AUTHKEY`.
- **Confirm before every `tofu apply`.** It creates billable resources.
