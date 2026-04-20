variable "name" {
  description = "Host name (also its Tailscale MagicDNS name)."
  type        = string
}

variable "location" {
  type = string
}

variable "type" {
  description = "Hetzner Cloud server type (cx22, cx32, ...)."
  type        = string
}

variable "public" {
  description = "If true, opens 443 and creates a DNS A record for the apex domain."
  type        = bool
  default     = false
}

variable "domain" {
  description = "Apex domain. Required when public = true."
  type        = string
  default     = ""
}

variable "user_data" {
  description = "Rendered cloud-init YAML."
  type        = string
  sensitive   = true
}

variable "image" {
  description = "Server image. Debian 12 by default."
  type        = string
  default     = "debian-12"
}

variable "backups" {
  description = "Enable Hetzner automatic Backups (weekly whole-disk snapshot, 7-day retention, +20% cost)."
  type        = bool
  default     = true
}

variable "ssh_keys" {
  description = "List of Hetzner SSH key IDs to inject into the server."
  type        = list(number)
  default     = []
}

variable "operator_ip" {
  description = "Operator's public IP for SSH access during bootstrap."
  type        = string
  default     = ""
}
