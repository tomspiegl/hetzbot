---
name: hetzbot-google
description: Shared Google Workspace API access (Gmail, Drive, etc.) for fleet services. Triggers: user says "add google", "gmail access", "google api". Interactive — walks through OAuth2 setup, token acquisition, and deployment.
---

# google

Shared Google OAuth2 credentials for Gmail API (send/receive), Drive,
Sheets, etc. One credential set per fleet; any service that needs
Google API access reads from `/etc/hetzbot/google/` on the host.

## Files

| File | Purpose |
|---|---|
| `SKILL.md` | This playbook. |
| `install.sh <host>` | Deploys credentials + token to the host. |
| `review.sh` | Checks token exists and is not expired. |

## How it works

Google APIs use OAuth2. Two files are needed:

1. **`google-credentials.json`** — the OAuth2 client ID + secret from
   Google Cloud Console. Created once per project.
2. **`google-token.json`** — the OAuth2 refresh token obtained via
   browser consent. Created once per Google account, refreshes
   automatically. Must be re-created if scopes change or token is
   revoked.

Both live in `/etc/hetzbot/google/` on the host (mode 0600, root-owned).
Services read them via symlink or env var pointing to that path.

## Program

```python
# 1. Check for existing credentials locally.

creds_dir = f"{env.HETZBOT_FLEET_ROOT}/.secrets/google"
creds_file = f"{creds_dir}/google-credentials.json"
token_file = f"{creds_dir}/google-token.json"

if path_exists(creds_file):
    inform(f"Found existing credentials: {creds_file}")
else:
    # 2. Guide operator through Google Cloud Console setup.
    inform("""No Google OAuth2 credentials found. Set them up:

  1. Go to https://console.cloud.google.com/apis/credentials
  2. Create a project (or select existing).
  3. Configure OAuth consent screen:
     - User type: Internal (if Google Workspace) or External
     - App name: hetzbot-fleet (or your choice)
     - Scopes: add gmail.readonly, gmail.send, drive (as needed)
  4. Create OAuth2 client ID:
     - Application type: Desktop app
     - Name: hetzbot
  5. Download the JSON → save as:
     {creds_file}""")

    run(f"mkdir -p {creds_dir}")

    while not path_exists(creds_file):
        if ask("Credentials file saved?", choices=["retry", "abort"]) == "abort":
            fail("no credentials file")

# 3. Determine scopes needed.

scopes = ask(
    "Which scopes? (comma-separated)",
    default="gmail.readonly,gmail.send",
)
# Common scopes:
#   gmail.readonly   — read emails + attachments
#   gmail.send       — send emails
#   gmail.modify     — read + send + modify labels
#   drive            — Google Drive full access
#   drive.readonly   — Google Drive read-only
#   spreadsheets     — Google Sheets

scope_urls = []
for s in scopes.split(","):
    s = s.strip()
    scope_urls.append(f"https://www.googleapis.com/auth/{s}")

# 4. Run OAuth2 consent flow (requires browser on operator machine).

if path_exists(token_file):
    reuse = ask("Existing token found. Re-use it?", choices=["yes", "no"])
    if reuse == "yes":
        inform("Using existing token.")
    else:
        run(f"rm {token_file}")

if not path_exists(token_file):
    inform("""Running OAuth2 consent flow...
  A browser window will open. Sign in with the Google account
  you want services to use, then approve the requested scopes.

  The fleet includes a helper script:
    bash $HETZBOT_FLEET_ROOT/scripts/google-auth.sh
  Or the operator can run it via: ! bash scripts/google-auth.sh""")

    run(f"python3 $HETZBOT_ROOT/skills/infra/google/auth-flow.py "
        f"--credentials {creds_file} "
        f"--token {token_file} "
        f"--scopes {','.join(scope_urls)}")

    if not path_exists(token_file):
        fail("token not created — consent flow may have failed")

# 5. Deploy to target host(s).

hosts = list(hosts_tfvars.keys())
if len(hosts) == 1:
    target = hosts[0]
else:
    target = ask("Deploy Google credentials to which host?", choices=hosts)

inform(f"Deploying credentials + token to {target}...")
run(f"ssh {target} 'install -d -m 0700 /etc/hetzbot/google'")
run(f"scp {creds_file} root@{target}:/etc/hetzbot/google/google-credentials.json")
run(f"scp {token_file} root@{target}:/etc/hetzbot/google/google-token.json")
run(f"ssh {target} 'chmod 0600 /etc/hetzbot/google/*'")

# 6. Verify on host.

run(f"ssh {target} 'ls -la /etc/hetzbot/google/'")

# 7. Done.

inform(f"""Google API credentials deployed to {target}.

Services can access them at:
  /etc/hetzbot/google/google-credentials.json
  /etc/hetzbot/google/google-token.json

To grant a service access, add to its .env:
  GOOGLE_CREDENTIALS_FILE=/etc/hetzbot/google/google-credentials.json
  GOOGLE_TOKEN_FILE=/etc/hetzbot/google/google-token.json

Token refreshes automatically. If it expires or scopes change,
re-run this skill to re-authenticate.""")
```

## Recovery

**Token expired / revoked.**
Re-run this skill. It will detect the existing credentials and only
redo the consent flow for a fresh token.

**Scopes changed.**
Delete the token file and re-run:
```
rm .secrets/google/google-token.json
```
The consent flow will request the new scopes.

**Wrong Google account.**
Delete both files and start over — the credentials are tied to the
Google Cloud project, not the account, but the token is account-specific.

## Rules

- **Credentials and tokens are secrets.** Never print, log, or commit them.
- **`.secrets/` is gitignored.** Keep it that way.
- **One credential set per fleet.** Multiple Google accounts are possible
  but use separate token files (pass `--account` to auth-flow.py).
