output "hosts" {
  description = "Per-host metadata consumed by skills/ops/deploy/deploy.sh."
  value = {
    for name, h in var.hosts : name => {
      location = h.location
      type     = h.type
      public   = h.public
      backups  = h.backups
      services = h.services
      ipv4     = module.host[name].ipv4
      ipv6     = module.host[name].ipv6
      hcloud_id = module.host[name].id
      # MagicDNS name — deploy.sh uses this, not the public IP.
      tailnet_host = name
    }
  }
}

output "public_hosts" {
  description = "Names of hosts with public = true (for Caddy assembly)."
  value       = [for name, h in var.hosts : name if h.public]
}
