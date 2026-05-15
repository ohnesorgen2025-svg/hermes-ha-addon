#!/command/with-contenv bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
HERMES_REPO="${HERMES_REPO:-https://github.com/ohnesorgen2025-svg/hermes-agent.git}"
HERMES_REF="${HERMES_REF:-main}"

export HERMES_HOME="/config/.hermes"
SRC_DIR="$HERMES_HOME/hermes-agent"
VENV_DIR="$SRC_DIR/venv"
ENV_FILE="$HERMES_HOME/.env"
CONFIG_FILE="$HERMES_HOME/config.yaml"
MARKER_FILE="$HERMES_HOME/.install_marker"
ADDON_SKILL_TEMPLATES_DIR="/addon-skill-templates"
SKILL_TEMPLATES_DIR="$HERMES_HOME/skill-templates"
ACTIVE_SKILLS_DIR="$HERMES_HOME/skills"
DEVICE_ONBOARDING_DATA_DIR="$HERMES_HOME/device_onboarding"
DEFAULT_SKILL_NAME="device-onboarding"
SKILL_SYNC_MARKER_NAME=".addon-managed-sha256"

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

seed_file_if_missing() {
    local source_path="$1"
    local target_path="$2"

    if [ ! -f "$source_path" ] || [ -f "$target_path" ]; then
        return
    fi

    mkdir -p "$(dirname "$target_path")"
    cp "$source_path" "$target_path"
}

compute_skill_hash() {
    local skill_dir="$1"

    if [ ! -d "$skill_dir" ]; then
        return 1
    fi

    (
        cd "$skill_dir"
        find . -type f ! -name "$SKILL_SYNC_MARKER_NAME" -print0 \
            | sort -z \
            | xargs -0 sha256sum
    ) | sha256sum | awk '{print $1}'
}

write_skill_sync_marker() {
    local skill_dir="$1"
    local skill_hash="$2"

    printf '%s\n' "$skill_hash" > "$skill_dir/$SKILL_SYNC_MARKER_NAME"
}

if [ -n "${TZ:-}" ] && [[ "${TZ}" != *..* ]] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

OLLAMA_API_KEY="$(config_value ollama_api_key "")"
OLLAMA_MODEL="$(config_value ollama_model "hermes3:latest")"
TELEGRAM_BOT_TOKEN="$(config_value telegram_bot_token "")"
TELEGRAM_ALLOWED_USERS="$(config_value telegram_allowed_users "")"
MQTT_HOST="$(config_value mqtt_host "core-mosquitto")"
MQTT_PORT="$(config_value mqtt_port "1883")"
MQTT_USER="$(config_value mqtt_user "")"
MQTT_PASSWORD="$(config_value mqtt_password "")"
ACCESS_PASSWORD="$(config_value access_password "")"
AUTO_UPDATE="$(config_bool auto_update)"

if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
    echo "[run] FATAL: SUPERVISOR_TOKEN is not set"
    exit 1
fi

mkdir -p "$HERMES_HOME" "$SKILL_TEMPLATES_DIR" "$ACTIVE_SKILLS_DIR" "$DEVICE_ONBOARDING_DATA_DIR"

echo "[run] Writing $ENV_FILE"
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"
write_env_var "OLLAMA_API_KEY" "$OLLAMA_API_KEY"
write_env_var "HASS_TOKEN" "$SUPERVISOR_TOKEN"
write_env_var "HASS_URL" "http://supervisor/core"
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    write_env_var "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
fi
if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    write_env_var "TELEGRAM_ALLOWED_USERS" "$TELEGRAM_ALLOWED_USERS"
fi
write_env_var "MQTT_HOST" "$MQTT_HOST"
write_env_var "MQTT_PORT" "$MQTT_PORT"
if [ -n "$MQTT_USER" ]; then
    write_env_var "MQTT_USER" "$MQTT_USER"
fi
if [ -n "$MQTT_PASSWORD" ]; then
    write_env_var "MQTT_PASSWORD" "$MQTT_PASSWORD"
fi
if [ -n "$ACCESS_PASSWORD" ]; then
    write_env_var "API_SERVER_KEY" "$ACCESS_PASSWORD"
fi

export OLLAMA_API_KEY
export HASS_TOKEN="$SUPERVISOR_TOKEN"
export HASS_URL="http://supervisor/core"
export MQTT_HOST
export MQTT_PORT
if [ -n "$MQTT_USER" ]; then
    export MQTT_USER
fi
if [ -n "$MQTT_PASSWORD" ]; then
    export MQTT_PASSWORD
fi
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    export TELEGRAM_BOT_TOKEN
fi
if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    export TELEGRAM_ALLOWED_USERS
fi
if [ -n "$ACCESS_PASSWORD" ]; then
    export API_SERVER_KEY="$ACCESS_PASSWORD"
fi

echo "[run] MQTT config: host=${MQTT_HOST:-<unset>} port=${MQTT_PORT:-<unset>} user_set=$([ -n "$MQTT_USER" ] && printf yes || printf no) password_set=$([ -n "$MQTT_PASSWORD" ] && printf yes || printf no)"

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

previous_template_skill_hash=""
if [ -d "$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME" ]; then
    previous_template_skill_hash="$(compute_skill_hash "$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME" 2>/dev/null || true)"
fi

if [ -d "$ADDON_SKILL_TEMPLATES_DIR" ]; then
    echo "[run] Installing bundled skill templates"
    rm -rf "$SKILL_TEMPLATES_DIR"
    mkdir -p "$SKILL_TEMPLATES_DIR"
    cp -R "$ADDON_SKILL_TEMPLATES_DIR"/. "$SKILL_TEMPLATES_DIR"/

    if [ -d "$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME" ]; then
        template_skill_dir="$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME"
        active_skill_dir="$ACTIVE_SKILLS_DIR/$DEFAULT_SKILL_NAME"
        template_skill_hash="$(compute_skill_hash "$template_skill_dir")"

        if [ ! -d "$active_skill_dir" ]; then
            echo "[run] Installing default $DEFAULT_SKILL_NAME skill"
            cp -R "$template_skill_dir" "$active_skill_dir"
            write_skill_sync_marker "$active_skill_dir" "$template_skill_hash"
        else
            active_skill_hash="$(compute_skill_hash "$active_skill_dir")"
            previous_managed_hash="$(cat "$active_skill_dir/$SKILL_SYNC_MARKER_NAME" 2>/dev/null || true)"

            if [ -n "$previous_managed_hash" ] && [ "$active_skill_hash" = "$previous_managed_hash" ] && [ "$active_skill_hash" != "$template_skill_hash" ]; then
                echo "[run] Updating managed $DEFAULT_SKILL_NAME skill"
                rm -rf "$active_skill_dir"
                cp -R "$template_skill_dir" "$active_skill_dir"
                write_skill_sync_marker "$active_skill_dir" "$template_skill_hash"
            elif [ -z "$previous_managed_hash" ] && [ -n "$previous_template_skill_hash" ] && [ "$active_skill_hash" = "$previous_template_skill_hash" ] && [ "$active_skill_hash" != "$template_skill_hash" ]; then
                echo "[run] Updating legacy managed $DEFAULT_SKILL_NAME skill"
                rm -rf "$active_skill_dir"
                cp -R "$template_skill_dir" "$active_skill_dir"
                write_skill_sync_marker "$active_skill_dir" "$template_skill_hash"
            elif [ -n "$previous_managed_hash" ] && [ "$active_skill_hash" != "$previous_managed_hash" ]; then
                echo "[run] Keeping customized $DEFAULT_SKILL_NAME skill"
            else
                echo "[run] Keeping existing $DEFAULT_SKILL_NAME skill"
            fi
        fi

        seed_file_if_missing \
            "$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME/data/known_devices.json" \
            "$DEVICE_ONBOARDING_DATA_DIR/known_devices.json"
        seed_file_if_missing \
            "$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME/data/known_devices.schema.json" \
            "$DEVICE_ONBOARDING_DATA_DIR/known_devices.schema.json"
    fi
fi

if [ -d "$SRC_DIR/.git" ]; then
    echo "[run] Updating Hermes Agent source from $HERMES_REPO ($HERMES_REF)..."
    git -C "$SRC_DIR" remote set-url origin "$HERMES_REPO"
    git -C "$SRC_DIR" fetch origin "$HERMES_REF"
    if git -C "$SRC_DIR" rev-parse --verify "origin/$HERMES_REF^{commit}" >/dev/null 2>&1; then
        git -C "$SRC_DIR" reset --hard "origin/$HERMES_REF"
    else
        git -C "$SRC_DIR" reset --hard FETCH_HEAD
    fi
else
    echo "[run] Cloning Hermes Agent from $HERMES_REPO ($HERMES_REF)..."
    git clone --branch "$HERMES_REF" "$HERMES_REPO" "$SRC_DIR"
fi
git -C "$SRC_DIR" submodule update --init --recursive || true

if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "[run] Creating Python environment..."
    uv venv "$VENV_DIR" --python 3.11
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

PYTHON_DEPS=("aiohttp>=3.9.0,<4" "paho-mqtt>=2.1.0,<3" "python-telegram-bot[webhooks]>=22.6,<23")
current_revision="$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
install_marker="${current_revision}|${PYTHON_DEPS[*]}"
if [ ! -f "$VENV_DIR/bin/hermes" ] || [ ! -f "$MARKER_FILE" ] || [ "$(cat "$MARKER_FILE" 2>/dev/null || true)" != "$install_marker" ]; then
    echo "[run] Installing Hermes Agent..."
    uv pip install -e "$SRC_DIR" "${PYTHON_DEPS[@]}"
    printf '%s\n' "$install_marker" > "$MARKER_FILE"
fi

echo "[run] Starting Hermes Gateway"
cd "$HERMES_HOME"
exec env \
    OLLAMA_API_KEY="$OLLAMA_API_KEY" \
    HASS_TOKEN="$SUPERVISOR_TOKEN" \
    HASS_URL="http://supervisor/core" \
    MQTT_HOST="$MQTT_HOST" \
    MQTT_PORT="$MQTT_PORT" \
    MQTT_USER="$MQTT_USER" \
    MQTT_PASSWORD="$MQTT_PASSWORD" \
    TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
    TELEGRAM_ALLOWED_USERS="$TELEGRAM_ALLOWED_USERS" \
    API_SERVER_KEY="$ACCESS_PASSWORD" \
    hermes gateway run
