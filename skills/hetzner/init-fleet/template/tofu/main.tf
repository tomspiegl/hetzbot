locals {
  user_data = {
    for name, h in var.hosts : name => templatefile("${path.module}/user-data.yaml.tpl", {
      hostname              = name
      public                = h.public
      tailscale_authkey     = var.tailscale_authkey
      console_root_password = var.console_root_password
      restic_repo           = "s3:${var.os_endpoint}/${name}"
      restic_password       = var.restic_password
      os_access_key         = var.os_access_key
      os_secret_key         = var.os_secret_key
      operator_ip           = var.operator_ip
    })
  }
}

module "host" {
  source = "./modules/host"

  for_each = var.hosts

  name      = each.key
  location  = each.value.location
  type      = each.value.type
  public    = each.value.public
  backups   = each.value.backups
  domain    = var.domain
  user_data = local.user_data[each.key]
  ssh_keys    = var.ssh_keys
  operator_ip = var.operator_ip
}
