#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[sync-skills] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
    log "FATAL: $*"
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
}

STATE_ROOT="${HERMES_HOME:-/config/.hermes}"
CONFIG_FILE="${HERMES_STATE_SYNC_CONFIG:-$STATE_ROOT/hermes-state-sync.env}"

if [ -f "$CONFIG_FILE" ]; then
    log "Loading config from $CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    log "No config file at $CONFIG_FILE; using built-in defaults and environment"
fi

SOURCE_DIR="${HERMES_STATE_SOURCE_DIR:-$STATE_ROOT/skills}"
REPO_SSH_URL="${HERMES_STATE_REPO_SSH_URL:-git@github.com:ohnesorgen2025-svg/hermes-state.git}"
DEPLOY_KEY_PATH="${HERMES_STATE_DEPLOY_KEY_PATH:-$STATE_ROOT/hermes-state-deploy-key}"
TARGET_BRANCH="${HERMES_STATE_BRANCH:-main}"
TARGET_SUBDIR="${HERMES_STATE_REMOTE_SUBDIR:-skills}"
WORK_ROOT="${HERMES_STATE_WORK_ROOT:-$STATE_ROOT/state-sync}"
GIT_NAME="${HERMES_STATE_GIT_NAME:-Hermes State Sync}"
GIT_EMAIL="${HERMES_STATE_GIT_EMAIL:-hermes-state-sync@local}"
LOCK_DIR="$WORK_ROOT/.lock"

cleanup() {
    local exit_code=$?
    if [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ]; then
        rm -rf "$RUN_DIR"
    fi
    if [ -d "$LOCK_DIR" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT

require_cmd find
require_cmd git
require_cmd grep
require_cmd rsync
require_cmd ssh
require_cmd ssh-keyscan
require_cmd sort
require_cmd mktemp

mkdir -p "$WORK_ROOT"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    fail "Another sync run is already in progress (lock: $LOCK_DIR)"
fi

RUN_DIR="$(mktemp -d "$WORK_ROOT/run.XXXXXX")"
REPO_DIR="$RUN_DIR/repo"
KNOWN_HOSTS_FILE="$RUN_DIR/known_hosts"
FILENAME_HITS="$RUN_DIR/filename_hits.txt"
CONTENT_HITS="$RUN_DIR/content_hits.txt"

log "Source directory: $SOURCE_DIR"
log "Target repository: $REPO_SSH_URL ($TARGET_BRANCH)"
log "Remote subdirectory: $TARGET_SUBDIR"

[ -f "$DEPLOY_KEY_PATH" ] || fail "Deploy key not found at $DEPLOY_KEY_PATH"
chmod 600 "$DEPLOY_KEY_PATH"

touch "$FILENAME_HITS" "$CONTENT_HITS"

if [ -d "$SOURCE_DIR" ]; then
    find "$SOURCE_DIR" -type f \( \
        -name '.env' -o -name '.env.*' -o \
        -name '*.pem' -o -name '*.key' -o \
        -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' -o \
        -name 'authorized_keys' \
    \) | sort > "$FILENAME_HITS"

    grep -RInI -E -- '-----BEGIN (RSA|DSA|EC|OPENSSH|PGP|PRIVATE) KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|(^|[^A-Za-z])(api[_-]?key|access[_-]?token|refresh[_-]?token|bearer|client[_-]?secret|private[_-]?key|password)\s*[:=]|(^|[^0-9])((25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])([^0-9]|$)' "$SOURCE_DIR" > "$CONTENT_HITS" || true
fi

if [ -s "$FILENAME_HITS" ] || [ -s "$CONTENT_HITS" ]; then
    log "Secret scan failed; refusing to commit runtime skills mirror"
    if [ -s "$FILENAME_HITS" ]; then
        log "Blocked file names:" 
        sed 's/^/[sync-skills]   /' "$FILENAME_HITS"
    fi
    if [ -s "$CONTENT_HITS" ]; then
        log "Blocked content matches:" 
        sed 's/^/[sync-skills]   /' "$CONTENT_HITS"
    fi
    exit 10
fi

log "Secret scan passed"

ssh-keyscan github.com > "$KNOWN_HOSTS_FILE" 2>/dev/null || fail "ssh-keyscan github.com failed"
export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KNOWN_HOSTS_FILE"

log "Cloning mirror repository"
git clone --depth 1 --branch "$TARGET_BRANCH" "$REPO_SSH_URL" "$REPO_DIR"
git -C "$REPO_DIR" config user.name "$GIT_NAME"
git -C "$REPO_DIR" config user.email "$GIT_EMAIL"

TARGET_DIR="$REPO_DIR/$TARGET_SUBDIR"

if [ -d "$SOURCE_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    log "Syncing skill tree into $TARGET_SUBDIR/"
    rsync -a --delete --exclude '.git/' "$SOURCE_DIR/" "$TARGET_DIR/"
else
    log "Source directory does not exist; mirroring empty state"
    rm -rf "$TARGET_DIR"
fi

git -C "$REPO_DIR" add -A

if [ -z "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" ]; then
    log "No content diff detected; nothing to commit"
    exit 0
fi

changed_paths="$(git -C "$REPO_DIR" diff --cached --name-only | tr '\n' ' ' | sed 's/[[:space:]]\+$//')"
log "Detected diff: $changed_paths"

commit_message="chore(sync): mirror runtime skills $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git -C "$REPO_DIR" commit -m "$commit_message"

log "Pushing mirror commit to $REPO_SSH_URL"
git -C "$REPO_DIR" push origin "$TARGET_BRANCH"
log "Sync completed successfully"