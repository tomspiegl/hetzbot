---
name: hetzbot-init-fleet
description: Scaffold a new fleet repo that consumes hetzbot as a sibling clone. Triggers: user says "init fleet", "bootstrap a new fleet repo", "create a new fleet". Generates a minimal repo with hosts.tfvars, services/, .env.example, justfile, and README.
---

# init-fleet

Generates a fresh fleet repository at a path you choose. The fleet
repo is tiny — it owns `hosts.tfvars`, `services/<name>/`, and a
local `.env`. Everything else (tofu, skills, scripts) stays in
hetzbot and is invoked via `HETZBOT_ROOT`.

## Program

```python
# 1. Gather inputs.

fleet_path = ask("Where to create the fleet repo? (e.g. ../my-fleet)")

# Three-way branch — filesystem *is* the state, so re-entering the
# skill after a partial run is safe.
if path_exists(fleet_path) and not is_empty_dir(fleet_path):
    if has_file(fleet_path, "hosts.tfvars") and has_file(fleet_path, ".env.example"):
        inform(f"{fleet_path} already scaffolded — resuming at git/inform steps")
    else:
        reject("path exists, is not empty, and doesn't look like a scaffolded fleet")

fleet_name = ask(
    "Fleet name? (used in README + commit messages)",
    default=basename(fleet_path),
)

git_init = ask(
    "Run git init in the new repo?",
    choices=["yes", "no"],
    default="yes",
)

# 2. Scaffold from template/.  The script is idempotent: if fleet_path
# already contains hosts.tfvars + .env.example, it exits 0 without
# touching anything.

run(f"bash $HETZBOT_ROOT/skills/hetzner/init-fleet/init-fleet.sh {fleet_path} {fleet_name}")

# 3. Git init + first commit — guarded so re-runs don't error.

if git_init == "yes":
    if not path_exists(f"{fleet_path}/.git"):
        run(f"git -C {fleet_path} init -b main")
    run(f"git -C {fleet_path} add .")
    if has_staged_changes(fleet_path):
        run(f'git -C {fleet_path} commit -m "scaffold {fleet_name} from hetzbot"')

# 4. Create .env and fill in manual credentials.

run(f"cp {fleet_path}/.env.example {fleet_path}/.env")
inform("""Open .env and fill in these from the Hetzner Console:
  HCLOUD_TOKEN          — Cloud Console → API Tokens
  AWS_ACCESS_KEY_ID     — Cloud Console → Security → S3 Credentials
  AWS_SECRET_ACCESS_KEY — (shown once when creating the S3 credential)""")
ask("Press enter once all three are set in .env")

# 5. Run setup-env.sh — creates the S3 bucket, generates
# RESTIC_PASSWORD and CONSOLE_ROOT_PASSWORD. All generated secrets
# are written directly into .env — they never appear in the conversation.

run(f"bash $HETZBOT_ROOT/skills/hetzner/init-fleet/setup-env.sh {fleet_path} {fleet_name}")

# 6. Operator fills optional values, then check-env validates.

inform("Optionally fill DOMAIN in .env (only needed for public hosts).")
run(f"bash $HETZBOT_ROOT/skills/hetzner/init-fleet/check-env.sh {fleet_path}")

# 7. Next steps.

inform(f"""Fleet ready at {fleet_path}.

Next:
  cd {fleet_path}
  tofu -chdir=tofu init  # one-time: initialize the S3 backend
  tofu -chdir=tofu plan  # preview before any apply

Add hosts with the add-host skill.
Add services with the add-service skill.""")
```

## What the scaffold contains

| File | Role |
|---|---|
| `.env.example` | Template for session credentials. Gitignored real file. |
| `.gitignore` | Ignores `.env`, `.terraform/`, `*.tfstate*`. |
| `hosts.tfvars` | Starts empty (`hosts = {}`). add-host skill appends. |
| `services/.gitkeep` | Placeholder so `services/` is tracked. |
| `justfile` | Thin wrapper: loads `.env`, delegates to `$HETZBOT_ROOT/justfile` with `HETZBOT_FLEET_ROOT=$(pwd)`. |
| `README.md` | One-page pointer at hetzbot + link to docs. |

## Versioning hetzbot

The fleet expects hetzbot as a sibling clone at `$HETZBOT_ROOT`
(relative path in `.env`; absolute if you prefer). To pin to a
specific hetzbot version:

```
git -C $HETZBOT_ROOT checkout <tag>
```

To track `main` and upgrade whenever you're ready:

```
git -C $HETZBOT_ROOT pull --ff-only
```

## When it's not needed

- You're testing hetzbot itself (work in the hetzbot repo directly;
  `HETZBOT_FLEET_ROOT` defaults to hetzbot's own dir).
- You already have a fleet repo — just ensure its `.env` sets
  `HETZBOT_ROOT=../hetzbot` (or wherever you cloned it).
