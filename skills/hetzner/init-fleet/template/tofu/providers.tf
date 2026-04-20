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
  apitoken = var.domain != "" ? var.hetzner_dns_token : "unused"
}
