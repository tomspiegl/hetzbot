---
name: hetzbot-github
description: Per-service GitHub deploy key automation. Triggers: a service's `services/<svc>/source` uses an SSH URL (`git@github.com:owner/repo.git[#ref]`). The operator-side helper `ensure-deploy-key.sh` generates a per-service ed25519 keypair on the host, registers the public key as a read-only deploy key on the repo via `gh`, and verifies SSH auth. Idempotent.
---

# github

Automates the per-service deploy-key model that hetzbot uses for cloning
private GitHub repos. Without this skill, the operator has to ssh-keygen
on the host, copy the public key, paste it into the GitHub repo settings,
and only then run `deploy.sh`. With this skill, `deploy.sh` does it.

## When it runs

Once per service per host, on the first deploy where the repo is private.
On subsequent deploys it's a no-op (idempotent — exits in ~1s).

## What `ensure-deploy-key.sh` does

```python
def ensure_deploy_key(host, service, repo):
    # 1. ed25519 keypair on the host, owned by the service user.
    #    /srv/<service>/.ssh/{id_ed25519, id_ed25519.pub, known_hosts}
    if not host.path_exists(f"/srv/{service}/.ssh/id_ed25519"):
        host.ssh_keygen_as(service, "ed25519", f"/srv/{service}/.ssh/id_ed25519")

    # 2. Pre-populate known_hosts so first clone doesn't prompt for fingerprint.
    if not host.path_exists(f"/srv/{service}/.ssh/known_hosts"):
        host.ssh_keyscan(service, "github.com")

    # 3. Compare against repo's existing deploy keys (gh api).
    pubkey = host.read(f"/srv/{service}/.ssh/id_ed25519.pub")
    if any(matches(pubkey, k) for k in gh_api(f"repos/{repo}/keys")):
        return  # already registered — nothing to do

    # 4. Register read-only.
    gh_api_post(f"repos/{repo}/keys",
                title=f"{host} ({service})",
                key=pubkey,
                read_only=True)

    # 5. Verify SSH auth from host to github.com works.
    if "successfully authenticated" not in host.ssh_test_as(service, "git@github.com"):
        warn("deploy key added but SSH auth check failed — DNS/propagation lag?")
```

## Convention

- **Per-service keypair, not per-host.** Each service has its own ed25519
  key under `/srv/<service>/.ssh/`. Compromising one service's key
  doesn't grant access to other services' repos.
- **Read-only.** Deploy keys never need write access — deploys clone
  + checkout, never push. The `read_only=true` flag is mandatory.
- **Title naming**: `<host> (<service>)`. Lets the operator recognise
  keys later in the repo's deploy-key list.
- **SSH URL convention**: services with a private repo use
  `git@github.com:owner/repo.git[#ref]` in `services/<svc>/source`.
  Public repos can stay on `https://...` and skip the deploy key.

## Operator prerequisites (one-time, on laptop)

- `gh` CLI installed (`brew install gh` on macOS).
- `gh auth login` completed for the GitHub user/org that owns the
  service repos. The user must have admin on the repo (deploy-key
  creation requires admin scope).

## Where it's wired in

`skills/ops/deploy/deploy.sh` calls
`skills/infra/github/ensure-deploy-key.sh <host> <svc> <owner/repo>`
before each service's `install-service.sh` if the source URL is
`git@github.com:...`. For HTTPS URLs (public repos) it's skipped.

## Failure modes

- `gh auth status` fails → operator must re-authenticate.
- `gh api repos/.../keys` returns 404 → the GitHub user lacks admin
  permissions on the repo, or the repo doesn't exist.
- Adding a duplicate key → GitHub returns 422; we never try to add
  a key that's already there (idempotency check before POST).
- SSH auth verification fails → registration succeeded but propagation
  lagged. Usually resolves in seconds; the script warns but doesn't
  fail (deploy will retry on next clone).

## Why deploy keys, not a PAT or GitHub App

| Option | Pros | Cons |
|---|---|---|
| **Deploy key (this)** | Per-repo, per-service scope; no expiry; verifiable in repo settings | One-time setup per service-repo pair |
| Org-wide PAT on host | Single secret to rotate | Single point of compromise — full read access to all repos |
| GitHub App | Short-lived tokens; revocable | App registration + private-key handling on host = more moving parts |

Deploy keys win on blast-radius (one repo, read-only) and zero-runtime-state
(no token to rotate, no expiry to forget).
