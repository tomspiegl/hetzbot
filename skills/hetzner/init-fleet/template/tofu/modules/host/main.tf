terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    hetznerdns = {
      source  = "timohirt/hetznerdns"
      version = "~> 2.2"
    }
  }
}

resource "hcloud_firewall" "this" {
  name = "fw-${var.name}"

  # ICMP — useful for ping, always allowed.
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Public hosts open 443 only. Port 80 is never opened — ACME uses
  # TLS-ALPN-01 on 443.
  dynamic "rule" {
    for_each = var.public ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "443"
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }
}

resource "hcloud_server" "this" {
  name        = var.name
  image       = var.image
  server_type = var.type
  location    = var.location
  user_data   = var.user_data
  backups     = var.backups

  firewall_ids = [hcloud_firewall.this.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    managed_by = "hetzbot"
    public     = tostring(var.public)
    backups    = tostring(var.backups)
  }

  lifecycle {
    # user_data changes after first boot don't re-run cloud-init —
    # avoid recreating the server on template edits.
    ignore_changes = [user_data, image]
  }
}

data "hetznerdns_zone" "this" {
  count = var.public ? 1 : 0
  name  = var.domain
}

resource "hetznerdns_record" "apex" {
  count   = var.public ? 1 : 0
  zone_id = data.hetznerdns_zone.this[0].id
  name    = var.name
  value   = hcloud_server.this.ipv4_address
  type    = "A"
  ttl     = 300
}

resource "hetznerdns_record" "apex_v6" {
  count   = var.public ? 1 : 0
  zone_id = data.hetznerdns_zone.this[0].id
  name    = var.name
  value   = hcloud_server.this.ipv6_address
  type    = "AAAA"
  ttl     = 300
}
