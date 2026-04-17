---
name: hetzbot-caddy
description: Install and manage Caddy reverse proxy on public hosts. Triggers: a host has `public = true`, or user says "install caddy". Assembles /etc/caddy/Caddyfile from per-service snippets, validates, reloads zero-downtime. Binds 443 only; TLS-ALPN-01 via Let's Encrypt on the same port.
---

# caddy

Apt-installed Caddy on public hosts. Binds **only 443**, no port-80
listener. Per-service HTTP routing lives in
`services/<name>/caddy.conf` snippets, assembled by `assemble.sh`.

## Files

| File | Purpose |
|---|---|
| `install.sh` | Adds Caddy's signed-by apt repo; installs `caddy`; writes the `/etc/caddy/Caddyfile` global block; registers the repo with unattended-upgrades. Idempotent. |
| `assemble.sh` | Assembles `/etc/caddy/Caddyfile` from the global block + every `services/*/caddy.conf`, runs `caddy validate`, reloads caddy. Refuses to reload if validation fails. |
| `review.sh` | Audits: caddy active, no port 80 listener, every Caddyfile site has a valid cert with >14 days to expiry. |

## Security posture

**TLS-ALPN-01 on 443.** Let's Encrypt issues certs via the ALPN
challenge on the same 443 Caddy already listens on. No port-80
listener is ever opened — any plaintext HTTP request is refused
(not redirected; that would require a port-80 listener).

**Global block** disables Caddy's default HTTP→HTTPS redirect and
pins trusted proxies:

```caddy
{
    auto_https disable_redirects
    servers {
        trusted_proxies static private_ranges
    }
}

(header_defaults) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }
}
```

Every per-service snippet opens with `import header_defaults`.

**`caddy validate` before reload.** `assemble.sh` validates the
assembled config before `systemctl reload caddy`. A broken snippet
fails the deploy rather than knocking out every other site.

**Cert storage at `/var/lib/caddy/`** — backed up by restic so that
a rebuilt host doesn't immediately hit Let's Encrypt rate limits
during recovery.

## When `install.sh` runs

`deploy.sh` calls this skill's `install.sh` when the target host has
`public = true` in `hosts.tfvars`. Idempotent — exits fast if caddy
is already installed.

## Review checks

- `CRITICAL` — caddy unit not active on a public host.
- `HIGH` — port 80 listener detected anywhere.
- `HIGH` — any vhost cert expires in <7 days.
- `MEDIUM` — any vhost cert expires in <14 days.
- `MEDIUM` — a Caddyfile site can't be reached for cert fetch
  (usually "cert hasn't been issued yet").
- `OK` — cert valid for ≥14 days.

## Per-service snippet shape

```caddy
# services/<name>/caddy.conf
<name>.example.com {
    import header_defaults
    reverse_proxy 127.0.0.1:<port>
}
```

The backend binds `127.0.0.1:<port>` (hardening rule — services
never bind `0.0.0.0`). Caddy is the only thing on the public
interfaces.
