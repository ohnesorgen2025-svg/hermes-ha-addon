#!/command/with-contenv bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
HERMES_GIT_URL="https://github.com/NousResearch/hermes-agent.git"

export HERMES_HOME="/config/.hermes"
SRC_DIR="$HERMES_HOME/hermes-agent"
VENV_DIR="$SRC_DIR/venv"
ENV_FILE="$HERMES_HOME/.env"
CONFIG_FILE="$HERMES_HOME/config.yaml"
MARKER_FILE="$HERMES_HOME/.install_marker"

config_value() {
    local key="$1"
    local default="${2:-}"

    if [ -f "$OPTIONS_FILE" ]; then
        jq -r --arg key "$key" --arg default "$default" '.[$key] // $default' "$OPTIONS_FILE"
        return
    fi

    printf '%s' "$default"
}

config_bool() {
    local key="$1"
    local value
    value="$(config_value "$key" "false")"
    case "$value" in
        true|True|TRUE|1|yes|Yes|YES|on|On|ON) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

write_env_var() {
    local name="$1"
    local value="$2"
    printf '%s=%s\n' "$name" "$value" >> "$ENV_FILE"
}

if [ -n "${TZ:-}" ] && [[ "${TZ}" != *..* ]] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

OLLAMA_API_KEY="$(config_value ollama_api_key "")"
OLLAMA_MODEL="$(config_value ollama_model "hermes3:latest")"
TELEGRAM_BOT_TOKEN="$(config_value telegram_bot_token "")"
ACCESS_PASSWORD="$(config_value access_password "")"
AUTO_UPDATE="$(config_bool auto_update)"

if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
    echo "[run] FATAL: SUPERVISOR_TOKEN is not set"
    exit 1
fi

mkdir -p "$HERMES_HOME"

echo "[run] Writing $ENV_FILE"
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"
write_env_var "OLLAMA_API_KEY" "$OLLAMA_API_KEY"
write_env_var "HASS_TOKEN" "$SUPERVISOR_TOKEN"
write_env_var "HASS_URL" "http://supervisor/core"
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    write_env_var "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
fi
if [ -n "$ACCESS_PASSWORD" ]; then
    write_env_var "API_SERVER_KEY" "$ACCESS_PASSWORD"
fi

if [ ! -f "$CONFIG_FILE" ]; then
        echo "[run] Creating first-run Hermes config"
        cat > "$CONFIG_FILE" << EOF
model:
    provider: ollama-cloud
    model: ${OLLAMA_MODEL}
platforms:
    homeassistant:
        enabled: true
    telegram:
        enabled: true
EOF
        chmod 600 "$CONFIG_FILE"
fi

if [ ! -d "$SRC_DIR/.git" ]; then
    echo "[run] Cloning Hermes Agent..."
    git clone "$HERMES_GIT_URL" "$SRC_DIR"
    git -C "$SRC_DIR" submodule update --init --recursive || true
fi

if [ "$AUTO_UPDATE" = "true" ]; then
    echo "[run] Updating Hermes Agent..."
    git -C "$SRC_DIR" pull --ff-only || echo "[run] Warning: git pull failed"
    git -C "$SRC_DIR" submodule update --init --recursive || true
fi

if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "[run] Creating Python environment..."
    uv venv "$VENV_DIR" --python 3.11
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

current_revision="$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ ! -f "$VENV_DIR/bin/hermes" ] || [ ! -f "$MARKER_FILE" ] || [ "$(cat "$MARKER_FILE" 2>/dev/null || true)" != "$current_revision" ]; then
    echo "[run] Installing Hermes Agent..."
    uv pip install -e "$SRC_DIR" "python-telegram-bot[webhooks]>=22.6,<23"
    printf '%s\n' "$current_revision" > "$MARKER_FILE"
fi

echo "[run] Starting Hermes Gateway"
cd "$HERMES_HOME"
exec hermes gateway run