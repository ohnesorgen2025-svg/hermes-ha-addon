# Skill Sync Mirror

This add-on ships a wrapper-managed Git bridge for the runtime skills directory at `/config/.hermes/skills/`.

The bridge is intentionally outside Hermes itself. Hermes gets no Git credentials and no direct push path. The wrapper-owned script performs the mirror push.

## What it does

- Reads the active runtime skill tree from `/config/.hermes/skills/`
- Runs a hard secret scan before any Git write
- Clones the private mirror repository over SSH with a dedicated deploy key
- Mirrors the skills into the repository subdirectory `skills/`
- Creates a Git commit only when there is a real content diff
- Pushes to `main`

## Daily trigger

The add-on starts a daily cron job at `17 3 * * *` inside the container.

The cron job runs the same script as the manual trigger:

```bash
/opt/hermes-addon/scripts/sync-skills.sh
```

The add-on image also installs a convenience symlink:

```bash
sync-skills
```

Cron output is appended to:

```bash
/config/.hermes/logs/skill-sync.log
```

## Secret scan

The sync is fail-closed. If the script sees likely sensitive material, it aborts before any commit or push.

Current hard blockers:

- `.env` files and `.env.*`
- SSH private key file names such as `id_rsa`, `id_ed25519`, `authorized_keys`, `*.pem`, `*.key`
- Private key headers like `-----BEGIN OPENSSH PRIVATE KEY-----`
- Common token/key signatures such as `ghp_`, `github_pat_`, `sk-`, `AIza`, Slack token prefixes with realistic full-token lengths
- Assignment-style secret fields such as `api_key=`, `access_token:`, `client_secret=` and similar when they carry non-placeholder literal values
- Public IPv4 addresses

False positives intentionally ignored:

- Placeholder values such as `xx...xxxx`, `<TOKEN>`, `REDACTED`, `example`, `dummy`
- Environment-variable references such as `os.getenv("OPENAI_API_KEY")` or `${API_KEY}`
- Private / localhost / link-local IPv4 addresses such as `127.0.0.1` and `192.168.x.x`

If any hit is found, the script exits non-zero and prints the matching file paths / lines.

## Deploy key setup

1. Create the private mirror repository. This wrapper expects by default:

```bash
git@github.com:ohnesorgen2025-svg/hermes-state.git
```

2. Create a dedicated SSH keypair for this one repository:

```bash
ssh-keygen -t ed25519 -f hermes-state-deploy-key -C "hermes-state deploy key"
```

3. In GitHub, open the `hermes-state` repository:

```text
Settings -> Deploy keys -> Add deploy key
```

4. Paste the public key and enable write access.

5. Copy the private key into the add-on persistent storage and lock permissions down:

```bash
cp hermes-state-deploy-key /config/.hermes/hermes-state-deploy-key
chmod 600 /config/.hermes/hermes-state-deploy-key
```

6. Optional: create `/config/.hermes/hermes-state-sync.env` if you want to override defaults.

Supported variables:

```bash
HERMES_STATE_REPO_SSH_URL=git@github.com:ohnesorgen2025-svg/hermes-state.git
HERMES_STATE_DEPLOY_KEY_PATH=/config/.hermes/hermes-state-deploy-key
HERMES_STATE_BRANCH=main
HERMES_STATE_REMOTE_SUBDIR=skills
HERMES_STATE_GIT_NAME=Hermes State Sync
HERMES_STATE_GIT_EMAIL=hermes-state-sync@local
```

## Manual test

1. Place a harmless test file in `/config/.hermes/skills/`.
2. Run the sync manually inside the add-on container:

```bash
sync-skills
```

3. Confirm the script logs one of these outcomes:

- `No content diff detected; nothing to commit`
- `Sync completed successfully`

4. Open the private `hermes-state` repository and verify the file appeared under `skills/`.

5. Add a test line containing a fake token or an IP address, rerun `sync-skills`, and verify the script aborts without creating a commit.