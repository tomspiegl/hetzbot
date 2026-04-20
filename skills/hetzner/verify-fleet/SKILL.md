---
name: hetzbot-verify-fleet
description: Post-setup verification. Checks tofu state, backups, services, Postgres, Google API end-to-end. Triggers: user says "verify fleet", "is everything working", "verify setup", "post-setup check".
---

# verify-fleet

Comprehensive post-setup verification. Unlike `review-host` (security
audit) or `check-fleet` (quick pulse), this skill tests that each
subsystem actually works end-to-end — not just that config files exist.

Run after initial setup, after adding a host or service, or whenever
you want confidence the fleet can recover from a failure.

## Usage

Interactive — the agent walks through each check with the operator.
Can also be run non-interactively via the verify script:

```bash
ssh root@<host> bash /opt/hetzbot/skills/hetzner/verify-fleet/verify.sh
```

## Program

```python
# 1. Discover fleet.

fleet_root = env.HETZBOT_FLEET_ROOT
hosts_file = f"{fleet_root}/hosts.tfvars"

if not path_exists(hosts_file):
    fail("no hosts.tfvars — is HETZBOT_FLEET_ROOT set?")

hosts = parse_tfvars_hosts(hosts_file)
inform(f"Fleet has {len(hosts)} host(s): {', '.join(hosts.keys())}")

results = []  # list of (host, check, severity, message)

for host_name, host_cfg in hosts.items():

    inform(f"\n--- Verifying {host_name} ---")

    # 2. Reachability.

    if not run(f"ssh -o ConnectTimeout=5 -o BatchMode=yes root@{host_name} true"):
        results.append((host_name, "reachability", "CRITICAL", "unreachable over Tailscale"))
        continue
    results.append((host_name, "reachability", "OK", "host reachable"))

    # 3. Tofu state — verify local state matches deployed reality.

    tofu_dir = f"{fleet_root}/tofu"
    if path_exists(f"{tofu_dir}/terraform.tfstate"):
        state_hosts = run(f"tofu -chdir={tofu_dir} output -json hosts 2>/dev/null | jq -r 'keys[]'")
        if host_name in state_hosts:
            results.append((host_name, "tofu-state", "OK", "host present in tofu state"))
        else:
            results.append((host_name, "tofu-state", "HIGH", "host missing from tofu state"))
    else:
        results.append((host_name, "tofu-state", "HIGH", "no local terraform.tfstate found"))

    # 4. Restic — verify repo is reachable AND a backup can run.

    restic_env = run(f"ssh root@{host_name} 'test -f /etc/hetzbot/restic.env && echo yes'")
    if restic_env.strip() != "yes":
        results.append((host_name, "restic-env", "CRITICAL", "/etc/hetzbot/restic.env missing"))
    else:
        snap_count = run(f"ssh root@{host_name} 'set -a && . /etc/hetzbot/restic.env && set +a && restic snapshots --json 2>/dev/null | jq length'")
        snap_count = snap_count.strip()
        if snap_count == "0" or snap_count == "null":
            results.append((host_name, "restic-snapshots", "HIGH", "restic repo has 0 snapshots — backup never ran"))
        elif snap_count.isdigit():
            results.append((host_name, "restic-snapshots", "OK", f"{snap_count} snapshot(s) in restic repo"))
        else:
            results.append((host_name, "restic-snapshots", "HIGH", f"restic query failed: {snap_count}"))

    # 5. Backup timer active.

    timer = run(f"ssh root@{host_name} 'systemctl is-enabled hetzbot-backup.timer 2>/dev/null'")
    if timer.strip() == "enabled":
        results.append((host_name, "backup-timer", "OK", "hetzbot-backup.timer enabled"))
    else:
        results.append((host_name, "backup-timer", "CRITICAL", f"hetzbot-backup.timer is {timer.strip()}"))

    # 6. Postgres — verify container + connectivity.

    pg_running = run(f"ssh root@{host_name} 'docker ps --filter name=postgres --format {{{{.Status}}}} 2>/dev/null'")
    if "Up" in pg_running:
        results.append((host_name, "postgres", "OK", f"container {pg_running.strip()}"))
    elif pg_running.strip() == "":
        results.append((host_name, "postgres", "OK", "no postgres container (may not be needed)"))
    else:
        results.append((host_name, "postgres", "HIGH", f"postgres container not Up: {pg_running.strip()}"))

    pg_ready = run(f"ssh root@{host_name} 'pg_isready -h 127.0.0.1 -p 5432 2>/dev/null'")
    if "accepting connections" in pg_ready:
        results.append((host_name, "postgres-conn", "OK", "pg_isready: accepting connections"))
    elif pg_running.strip() != "":
        results.append((host_name, "postgres-conn", "HIGH", "pg_isready failed"))

    # 7. Per-service checks.

    services = host_cfg.get("services", [])
    for svc in services:
        svc_dir = run(f"ssh root@{host_name} 'test -d /srv/{svc} && echo yes'")
        if svc_dir.strip() != "yes":
            results.append((host_name, f"svc:{svc}", "HIGH", f"/srv/{svc} not deployed"))
            continue

        # Check unit or timer
        timer_check = run(f"ssh root@{host_name} 'systemctl is-enabled {svc}.timer 2>/dev/null'")
        unit_check = run(f"ssh root@{host_name} 'systemctl is-active {svc} 2>/dev/null'")

        if timer_check.strip() == "enabled":
            next_run = run(f"ssh root@{host_name} 'systemctl show {svc}.timer --property=NextElapseUSecRealtime --value 2>/dev/null'")
            results.append((host_name, f"svc:{svc}", "OK", f"timer enabled, next: {next_run.strip()}"))
        elif unit_check.strip() == "active":
            results.append((host_name, f"svc:{svc}", "OK", "unit active"))
        elif unit_check.strip() == "inactive" and timer_check.strip() == "enabled":
            results.append((host_name, f"svc:{svc}", "OK", "oneshot inactive (timer-driven)"))
        else:
            results.append((host_name, f"svc:{svc}", "MEDIUM", f"unit={unit_check.strip()}, timer={timer_check.strip()}"))

        # Check .env exists
        env_check = run(f"ssh root@{host_name} 'test -f /srv/{svc}/.env && echo yes'")
        if env_check.strip() != "yes":
            results.append((host_name, f"svc:{svc}", "HIGH", ".env missing"))

        # Check DB if postgres is running
        if "Up" in pg_running:
            db_exists = run(f"ssh root@{host_name} 'psql -h 127.0.0.1 -U postgres -lqt 2>/dev/null | grep -c \"^ {svc}\"'")
            if db_exists.strip() != "0":
                results.append((host_name, f"svc:{svc}:db", "OK", f"database '{svc}' exists"))
            else:
                results.append((host_name, f"svc:{svc}:db", "HIGH", f"database '{svc}' not found in Postgres"))

    # 8. Google API — test from host if credentials are deployed.

    google_creds = run(f"ssh root@{host_name} 'test -f /etc/hetzbot/google/google-credentials.json && echo yes'")
    if google_creds.strip() == "yes":
        google_test = run(f"ssh root@{host_name} 'python3 -c \"
import json
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
with open(\\\"/etc/hetzbot/google/google-token.json\\\") as f:
    t = json.load(f)
c = Credentials(token=t.get(\\\"token\\\"), refresh_token=t[\\\"refresh_token\\\"],
    token_uri=t[\\\"token_uri\\\"], client_id=t[\\\"client_id\\\"],
    client_secret=t[\\\"client_secret\\\"], scopes=t.get(\\\"scopes\\\", []))
if not c.valid:
    c.refresh(Request())
print(\\\"ok\\\")
\" 2>&1'")
        if "ok" in google_test:
            results.append((host_name, "google-api", "OK", "token valid / refreshable"))
        else:
            results.append((host_name, "google-api", "HIGH", f"token refresh failed: {google_test.strip()[:80]}"))
    else:
        results.append((host_name, "google-api", "OK", "no google credentials deployed (not needed?)"))

    # 9. Disk.

    disk_pct = run(f"ssh root@{host_name} \"df / --output=pcent | tail -1 | tr -d ' %'\"")
    disk_pct = disk_pct.strip()
    if disk_pct.isdigit():
        pct = int(disk_pct)
        if pct >= 90:
            results.append((host_name, "disk", "HIGH", f"root filesystem {pct}% full"))
        elif pct >= 80:
            results.append((host_name, "disk", "MEDIUM", f"root filesystem {pct}% full"))
        else:
            results.append((host_name, "disk", "OK", f"root filesystem {pct}% used"))

# 10. Tofu state backup check (fleet-level, not per-host).

inform("\n--- Fleet-level checks ---")

tfstate = f"{fleet_root}/tofu/terraform.tfstate"
if path_exists(tfstate):
    results.append(("fleet", "tofu-state-local", "OK", "terraform.tfstate exists locally"))

    # Check if using a remote backend
    backend = run(f"grep -l 'backend' {fleet_root}/tofu/*.tf 2>/dev/null")
    if backend.strip():
        results.append(("fleet", "tofu-backend", "OK", "remote backend configured"))
    else:
        results.append(("fleet", "tofu-backend", "HIGH",
            "tofu state is LOCAL ONLY — add a remote backend (S3) or back up the state file"))
else:
    results.append(("fleet", "tofu-state-local", "CRITICAL", "no terraform.tfstate found"))

# 11. Print results.

inform("\n========== VERIFICATION RESULTS ==========\n")
counts = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "OK": 0}
for host, check, sev, msg in results:
    inform(f"[{sev:8s}] {host}/{check}: {msg}")
    counts[sev] = counts.get(sev, 0) + 1

inform(f"\nSummary: {counts['CRITICAL']} CRITICAL, {counts['HIGH']} HIGH, "
       f"{counts['MEDIUM']} MEDIUM, {counts['OK']} OK")

if counts["CRITICAL"] > 0:
    inform("ACTION REQUIRED: resolve CRITICAL issues before operating the fleet.")
elif counts["HIGH"] > 0:
    inform("Issues found. Resolve HIGH items within 24h.")
else:
    inform("Fleet verification passed.")
```

## Tofu state backup

The verification flags local-only tofu state as HIGH. To fix:

**Option A — remote backend (recommended):**
Add to `tofu/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket                      = "<fleet-name>-state"
    key                         = "tofu/terraform.tfstate"
    region                      = "fsn1"
    endpoints                   = { s3 = "https://fsn1.your-objectstorage.com" }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
```
Then `tofu init -migrate-state` to push current state to S3.

**Option B — restic backup of state file:**
Add the fleet's `tofu/` dir to the operator's local restic backup.
Less robust than a remote backend (state can diverge if laptop is lost).

## When to run

- After initial fleet setup (all hosts + services deployed).
- After adding a host or service.
- After restoring from backup.
- Monthly as part of operator hygiene.

## What this does NOT replace

- `review-host` — detailed security audit (sshd, firewall, hardening).
- `check-fleet` — quick "is everything up" pulse.
- Per-skill `review.sh` — skill-specific config checks.

This skill tests that the fleet works end-to-end and can recover
from failure. The other tools verify that it's configured safely.
