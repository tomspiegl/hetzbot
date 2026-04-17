# {{FLEET_NAME}} — fleet definition.
# Each entry creates one Hetzner Cloud server + firewall + optional
# DNS record. Committed to git — no secrets go here.
#
# Add hosts via hetzbot's add-host skill. It'll append to this file.

hosts = {
  # Example (uncomment + edit):
  #
  # hetz-1 = {
  #   location = "nbg1"       # nbg1 | fsn1 | hel1 | ash | hil
  #   type     = "cx22"       # cx22 (4GB) | cx32 (8GB) | cx42 (16GB)
  #   public   = false
  #   backups  = true         # Hetzner weekly whole-disk snapshot, +20% cost
  #   services = []
  # }
}
