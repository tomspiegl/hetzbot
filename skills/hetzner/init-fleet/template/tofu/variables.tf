variable "hosts" {
  description = "Fleet definition — one entry per Hetzner Cloud server."
  type = map(object({
    location = string
    type     = string
    public   = optional(bool, false)
    services = optional(list(string), [])
    # Hetzner automatic Backups: weekly whole-disk snapshot, 7-day retention,
    # +20% of server cost. Complements restic (data recovery to a new host);
    # this is for "rebuild yesterday's box" recovery. Default on.
    backups  = optional(bool, true)
  }))
}

variable "domain" {
  description = "Apex domain for public hosts (only used when public = true)."
  type        = string
  default     = ""
}

variable "hetzner_dns_token" {
  description = "Hetzner DNS API token. Only required when DOMAIN is set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_authkey" {
  description = "Tailscale pre-auth key. Single-use, tag:host. Consumed at first boot."
  type        = string
  sensitive   = true
}

variable "console_root_password" {
  description = "Root password for the Hetzner web console fallback. SSH will not accept it."
  type        = string
  sensitive   = true
}

variable "restic_repo" {
  description = "Restic S3 URL for host-initiated backups."
  type        = string
}

variable "restic_password" {
  description = "Restic encryption password."
  type        = string
  sensitive   = true
}

variable "os_access_key" {
  description = "Hetzner Object Storage access key (for restic on the host)."
  type        = string
  sensitive   = true
}

variable "os_secret_key" {
  description = "Hetzner Object Storage secret key (for restic on the host)."
  type        = string
  sensitive   = true
}

variable "ssh_keys" {
  description = "Hetzner SSH key IDs to inject (for initial access before Tailscale)."
  type        = list(number)
  default     = []
}

variable "operator_ip" {
  description = "Operator's public IP. Allows SSH during bootstrap; removed after Tailscale join."
  type        = string
  default     = ""
}
