terraform {
  required_version = ">= 1.7"

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

provider "hcloud" {
  # Reads HCLOUD_TOKEN from env.
}

provider "hetznerdns" {
  # Reads HETZNER_DNS_API_TOKEN from env. Only used when any host
  # has public = true.
}
