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
| `auth-flow.py` | OAuth2 consent flow (runs on operator laptop). |
| `test-gmail.py` | Sends a test email from the host to verify setup. |

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

## Prerequisites

Before starting, enable these APIs in Google Cloud Console:

- **Gmail API**: `https://console.developers.google.com/apis/api/gmail.googleapis.com/overview?project=<PROJECT_ID>`
- **Drive API**: `https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=<PROJECT_ID>`
- **Sheets API**: `https://console.developers.google.com/apis/api/sheets.googleapis.com/overview?project=<PROJECT_ID>`

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
  3. Enable APIs: Gmail, Drive, Sheets (see Prerequisites above).
  4. Configure OAuth consent screen:
     - User type: Internal (if Google Workspace) or External
     - App name: your fleet name or org name
     - Scopes: add gmail.readonly, gmail.send, drive (as needed)
  5. Create OAuth2 client ID:
     - Application type: Desktop app
     - Name: hetzbot
  6. Download the JSON → save as:
     {creds_file}""")

    run(f"mkdir -p {creds_dir}")

    while not path_exists(creds_file):
        if ask("Credentials file saved?", choices=["retry", "abort"]) == "abort":
            fail("no credentials file")

# 3. Determine scopes needed.

scopes = ask(
    "Which scopes? (comma-separated)",
    default="gmail.readonly,gmail.send,gmail.modify,drive,spreadsheets",
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
  The fleet includes a helper script that opens a browser for consent:
    ! bash $HETZBOT_FLEET_ROOT/scripts/google-auth.sh

  Or run directly:
    ! python3 $HETZBOT_ROOT/skills/infra/google/auth-flow.py \\
        --credentials {creds_file} \\
        --token {token_file} \\
        --scopes <scope_urls>""")

    while not path_exists(token_file):
        if ask("Token file created?", choices=["retry", "abort"]) == "abort":
            fail("no token file")

# 5. Deploy to target host(s).

hosts = list(hosts_tfvars.keys())
if len(hosts) == 1:
    target = hosts[0]
else:
    target = ask("Deploy Google credentials to which host?", choices=hosts)

inform(f"Deploying credentials + token to {target}...")
run(f"ssh root@{target} 'install -d -m 0700 /etc/hetzbot/google'")
run(f"scp {creds_file} root@{target}:/etc/hetzbot/google/google-credentials.json")
run(f"scp {token_file} root@{target}:/etc/hetzbot/google/google-token.json")
run(f"ssh root@{target} 'chmod 0600 /etc/hetzbot/google/*'")

# 6. Install Python google libraries on host for token refresh + testing.

run(f"ssh root@{target} 'pip3 install --break-system-packages -q google-auth google-auth-oauthlib google-api-python-client'")

# 7. Test from the host — send a test email.

test_email = ask("Send test email to?", default=env.USER_EMAIL or "")
run(f"ssh root@{target} 'python3 /opt/hetzbot/skills/infra/google/test-gmail.py {test_email}'")
# Confirms: authenticated as <sender>, email sent, message ID returned.

# 8. Remove local secrets (they live on the host now).

inform("Credentials deployed and verified. Removing local copies...")
run(f"rm -f {creds_file} {token_file}")
# The fleet's .secrets/google/ dir stays (gitignored) for future re-auth.

# 9. Wire up services that need Google access.

inform(f"""Google API credentials deployed to {target} and tested.
Local copies removed — secrets live only on the host.

To grant a service access, add to its .env:
  GOOGLE_CREDENTIALS_FILE=/etc/hetzbot/google/google-credentials.json
  GOOGLE_TOKEN_FILE=/etc/hetzbot/google/google-token.json

Token refreshes automatically. If it expires or scopes change,
re-run the auth flow (scripts/google-auth.sh) and redeploy.""")
```

## Recovery

**Token expired / revoked.**
Re-run the auth flow on the operator laptop, then redeploy:
```
bash $HETZBOT_FLEET_ROOT/scripts/google-auth.sh
bash $HETZBOT_ROOT/skills/infra/google/install.sh <host>
```

**Scopes changed.**
Delete the local token file and re-run the auth flow:
```
rm .secrets/google/google-token.json
bash $HETZBOT_FLEET_ROOT/scripts/google-auth.sh
bash $HETZBOT_ROOT/skills/infra/google/install.sh <host>
```

**API not enabled.**
Enable at `https://console.developers.google.com/apis/api/<api>.googleapis.com/overview?project=<PROJECT_ID>`.
Common APIs: `gmail`, `drive`, `sheets`.

**Wrong Google account.**
Delete both files and start over — the credentials are tied to the
Google Cloud project, not the account, but the token is account-specific.

## Rules

- **Credentials and tokens are secrets.** Never print, log, or commit them.
- **`.secrets/` is gitignored.** Keep it that way.
- **Local copies are temporary.** After deploying to the host, remove them.
- **One credential set per fleet.** Multiple Google accounts are possible
  but use separate token files (pass `--account` to auth-flow.py).
