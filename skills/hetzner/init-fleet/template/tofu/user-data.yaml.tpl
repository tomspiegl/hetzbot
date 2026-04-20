#cloud-config
# hetzbot host bootstrap — minimal base.
# Installs only what's needed before the agent can reach the host:
# Tailscale (network), ufw (firewall), sshd hardening, unattended-upgrades.
# Everything else (docker, restic, caddy, runtimes) is a skill installed
# on-demand by deploy.sh. Headless by default.

hostname: ${hostname}
fqdn: ${hostname}
preserve_hostname: false

package_update: true
package_upgrade: true

packages:
  - ca-certificates
  - curl
  - gnupg
  - git
  - ufw
  - unattended-upgrades
  - needrestart
  - debsecan
  - jq
  - zstd
  - rsync

ssh_pwauth: false

chpasswd:
  expire: false
  list:
    - root:${console_root_password}

write_files:
  # --- unattended-upgrades with third-party origins ---
  - path: /etc/apt/apt.conf.d/50unattended-upgrades
    permissions: "0644"
    content: |
      Unattended-Upgrade::Origins-Pattern {
          "origin=Debian,codename=$${distro_codename},label=Debian";
          "origin=Debian,codename=$${distro_codename},label=Debian-Security";
          "origin=Debian,codename=$${distro_codename}-security,label=Debian-Security";
          "origin=download.docker.com,codename=$${distro_codename}";
          "origin=deb.nodesource.com";
          "origin=cloudsmith,label=Caddy";
          "origin=apt.postgresql.org,codename=$${distro_codename}-pgdg";
      };
      Unattended-Upgrade::Automatic-Reboot "true";
      Unattended-Upgrade::Automatic-Reboot-Time "04:00";
      Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";

  - path: /etc/apt/apt.conf.d/20auto-upgrades
    permissions: "0644"
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";

  # --- needrestart: auto-restart services whose libs were patched ---
  - path: /etc/needrestart/conf.d/99hetzbot.conf
    permissions: "0644"
    content: |
      $nrconf{restart} = 'a';

  # --- journald cap ---
  - path: /etc/systemd/journald.conf.d/hetzbot.conf
    permissions: "0644"
    content: |
      [Journal]
      SystemMaxUse=2G
      SystemKeepFree=1G

  # --- SSH hardening (Tailscale-only) ---
  - path: /etc/ssh/sshd_config.d/99-hetzbot.conf
    permissions: "0644"
    content: |
      PermitRootLogin prohibit-password
      PasswordAuthentication no
      PubkeyAuthentication yes
      KbdInteractiveAuthentication no
      AuthenticationMethods publickey

  # --- sshd must start after tailscaled (ListenAddress is Tailscale IP) ---
  - path: /etc/systemd/system/ssh.service.d/after-tailscale.conf
    permissions: "0644"
    content: |
      [Unit]
      After=tailscaled.service
      Wants=tailscaled.service

  # --- Operator CLI helpers dir ---
  - path: /opt/hetzbot/README
    permissions: "0644"
    content: |
      hetzbot runtime files. Do not edit by hand — managed by deploy.sh.

  # --- Restic env (read by backup-now.sh) ---
  - path: /etc/hetzbot/restic.env
    permissions: "0600"
    content: |
      RESTIC_REPOSITORY=${restic_repo}
      RESTIC_PASSWORD=${restic_password}
      AWS_ACCESS_KEY_ID=${os_access_key}
      AWS_SECRET_ACCESS_KEY=${os_secret_key}

  # --- Backup timer + service (installed; backup-now.sh comes via deploy.sh) ---
  - path: /etc/systemd/system/hetzbot-backup.service
    permissions: "0644"
    content: |
      [Unit]
      Description=hetzbot nightly backup
      After=network-online.target
      Wants=network-online.target
      # docker is wanted (the postgres component needs it), but not
      # required — a host without docker still runs the restic pass
      # over /srv /var/backups /etc /var/log/archive /var/lib/caddy.
      Wants=docker.service

      [Service]
      Type=oneshot
      EnvironmentFile=/etc/hetzbot/restic.env
      ExecStart=/opt/hetzbot/skills/ops/deploy/backup-now.sh

  - path: /etc/systemd/system/hetzbot-backup.timer
    permissions: "0644"
    content: |
      [Unit]
      Description=hetzbot nightly backup (02:30)

      [Timer]
      OnCalendar=*-*-* 02:30:00
      Persistent=true
      RandomizedDelaySec=15m

      [Install]
      WantedBy=timers.target

runcmd:
  # --- apt keyrings for the bootstrap-critical repo (Tailscale only) ---
  - install -d -m 0755 /etc/apt/keyrings

  # Tailscale (bootstrap — agent can't reach host without it)
  - curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
  - chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg
  - curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list > /dev/null

  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale
  # Docker, restic, caddy, language runtimes install on first deploy
  # via their respective skills (skills/infra/{docker,restic,caddy}/,
  # skills/runtimes/{node,python}/). This keeps the base host tiny.

  # --- Firewall ---
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow in on tailscale0
  - ufw allow from ${operator_ip} to any port 22 proto tcp
  - |
    if [ "${public}" = "true" ]; then
      ufw allow 443/tcp
    fi
  - ufw --force enable

  # --- Directories ---
  - install -d -m 0755 /srv
  - install -d -m 0755 /opt/hetzbot/skills
  - install -d -m 0755 /opt/hetzbot/services
  - install -d -m 0755 /var/log/archive
  - install -d -m 0755 /var/backups/pg
  - install -d -m 0700 /etc/hetzbot

  # --- Tailscale join ---
  - systemctl enable --now tailscaled
  - tailscale up --authkey=${tailscale_authkey} --ssh --hostname=${hostname} --accept-routes

  # --- journald reload ---
  - systemctl restart systemd-journald

  # --- SSH: reload hardened config ---
  - systemctl reload ssh

  # --- unattended-upgrades ---
  - systemctl enable --now unattended-upgrades

  # --- Backup timer enabled (backup-now.sh installed by deploy.sh) ---
  - systemctl daemon-reload
  - systemctl enable hetzbot-backup.timer

  # --- Done. deploy.sh from the operator picks up from here. ---
  - touch /var/lib/cloud/hetzbot-ready

power_state:
  mode: reboot
  condition: True
  delay: 1
  message: "hetzbot bootstrap complete — rebooting to apply kernel/libc updates"
