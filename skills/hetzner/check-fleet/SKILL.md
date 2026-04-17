---
name: hetzbot-check-fleet
description: Check every host and its services are up. Triggers: user says "is everything up", "status", "health check", "what's the state of the fleet".
---

# Check health

Use when the user wants a quick pulse on the fleet.

## Steps

1. List every host in the fleet:
   ```
   tofu -chdir=tofu output -json hosts | jq -r 'keys[]'
   ```
2. For each host `$H`:
   ```
   ssh $H uptime
   ssh $H 'systemctl list-units --type=service --state=running | head -20'
   ```
3. For any host that doesn't answer, check Tailscale:
   ```
   tailscale status | grep $H
   ```
   If offline:
   - `hcloud server list` (Hetzner API — requires HCLOUD_TOKEN in env).
   - Use the Hetzner web console (VNC) to inspect `journalctl -u cloud-final` and `journalctl -u tailscaled`.
4. For any service in `hosts.tfvars` that's not running:
   ```
   ssh $H systemctl status <service>
   ssh $H journalctl -u <service> -n 100
   ```
5. Backup health:
   ```
   ssh $H systemctl status hetzbot-backup.timer
   ssh $H sudo restic snapshots | tail
   ```
6. Disk pressure (alert at 80%):
   ```
   ssh $H df -h /
   ```

## Notes

- Tailscale admin log shows which operator last connected to which host.
- Healthchecks.io (if configured) is the external "is the host silent" signal.
