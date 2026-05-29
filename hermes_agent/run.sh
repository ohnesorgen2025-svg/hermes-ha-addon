#!/command/with-contenv bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
HERMES_REPO="${HERMES_REPO:-https://github.com/ohnesorgen2025-svg/hermes-agent.git}"
PINNED_HERMES_REF="${PINNED_HERMES_REF:-33a5bf64ce058b6cc6f5d4df4d7f042873d405c1}"
REQUESTED_HERMES_REF="${HERMES_REF:-}"

export HERMES_HOME="/config/.hermes"
SRC_DIR="$HERMES_HOME/hermes-agent"
VENV_DIR="$SRC_DIR/venv"
ENV_FILE="$HERMES_HOME/.env"
CONFIG_FILE="$HERMES_HOME/config.yaml"
MARKER_FILE="$HERMES_HOME/.install_marker"
ADDON_SKILL_TEMPLATES_DIR="/addon-skill-templates"
SKILL_TEMPLATES_DIR="$HERMES_HOME/skill-templates"
ACTIVE_SKILLS_DIR="$HERMES_HOME/skills"
SKILL_BACKUP_DIR="$HERMES_HOME/skill-backups"
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

sync_ollama_model_config() {
    local config_file="$1"
    local model_name="$2"

    python3 - "$config_file" "$model_name" << 'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
model_name = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()

start = None
end = len(lines)
for index, line in enumerate(lines):
    if line.strip() == "model:" and line == line.lstrip():
        start = index
        break

if start is None:
    sys.exit(0)

for index in range(start + 1, len(lines)):
    if lines[index].strip() and lines[index] == lines[index].lstrip():
        end = index
        break

section = lines[start + 1:end]
if not any(line.strip() == "provider: ollama-cloud" for line in section):
    sys.exit(0)

model_index = None
indent = "    "
for index in range(start + 1, end):
    if lines[index].lstrip() != lines[index] and lines[index].strip().startswith("model:"):
        model_index = index
        indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
        break

escaped_model = model_name.replace('\\', '\\\\').replace('"', '\\"')
model_line = f'{indent}model: "{escaped_model}"'

if model_index is None:
    insert_at = start + 1
    for index in range(start + 1, end):
        if lines[index].strip().startswith("provider:"):
            insert_at = index + 1
            indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
            model_line = f'{indent}model: "{escaped_model}"'
            break
    lines.insert(insert_at, model_line)
else:
    if lines[model_index] == model_line:
        sys.exit(0)
    lines[model_index] = model_line

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
    chmod 600 "$config_file"
}

resolve_hermes_ref() {
    if git -C "$SRC_DIR" rev-parse --verify "$HERMES_REF^{commit}" >/dev/null 2>&1; then
        git -C "$SRC_DIR" rev-parse --verify "$HERMES_REF^{commit}"
        return
    fi

    if git -C "$SRC_DIR" rev-parse --verify "origin/$HERMES_REF^{commit}" >/dev/null 2>&1; then
        git -C "$SRC_DIR" rev-parse --verify "origin/$HERMES_REF^{commit}"
        return
    fi

    if git -C "$SRC_DIR" rev-parse --verify "refs/tags/$HERMES_REF^{commit}" >/dev/null 2>&1; then
        git -C "$SRC_DIR" rev-parse --verify "refs/tags/$HERMES_REF^{commit}"
        return
    fi

    return 1
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

if [ -n "$REQUESTED_HERMES_REF" ]; then
    HERMES_REF="$REQUESTED_HERMES_REF"
elif [ "$AUTO_UPDATE" = "true" ]; then
    HERMES_REF="main"
else
    HERMES_REF="$PINNED_HERMES_REF"
fi

if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
    echo "[run] FATAL: SUPERVISOR_TOKEN is not set"
    exit 1
fi

mkdir -p "$HERMES_HOME" "$SKILL_TEMPLATES_DIR" "$ACTIVE_SKILLS_DIR" "$SKILL_BACKUP_DIR" "$DEVICE_ONBOARDING_DATA_DIR"

echo "[run] Writing $ENV_FILE"
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"
write_env_var "OLLAMA_API_KEY" "$OLLAMA_API_KEY"
write_env_var "OLLAMA_MODEL" "$OLLAMA_MODEL"
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
export OLLAMA_MODEL
export HASS_TOKEN="$SUPERVISOR_TOKEN"
export HASS_URL="http://supervisor/core"
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    export TELEGRAM_BOT_TOKEN
fi
if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    export TELEGRAM_ALLOWED_USERS
fi
export MQTT_HOST
export MQTT_PORT
if [ -n "$MQTT_USER" ]; then
    export MQTT_USER
fi
if [ -n "$MQTT_PASSWORD" ]; then
    export MQTT_PASSWORD
fi
if [ -n "$ACCESS_PASSWORD" ]; then
    export API_SERVER_KEY="$ACCESS_PASSWORD"
fi

echo "[run] MQTT config: host=$MQTT_HOST port=$MQTT_PORT user_set=$([ -n "$MQTT_USER" ] && printf yes || printf no) password_set=$([ -n "$MQTT_PASSWORD" ] && printf yes || printf no)"

if [ ! -f "$CONFIG_FILE" ]; then
        echo "[run] Creating first-run Hermes config"
        cat > "$CONFIG_FILE" << EOF
model:
    provider: ollama-cloud
    model: "${OLLAMA_MODEL}"
platforms:
    homeassistant:
        enabled: true
    telegram:
        enabled: true
EOF
        chmod 600 "$CONFIG_FILE"
else
    echo "[run] Syncing Ollama model setting into existing Hermes config when managed"
    sync_ollama_model_config "$CONFIG_FILE" "$OLLAMA_MODEL"
fi

if [ -d "$ADDON_SKILL_TEMPLATES_DIR" ]; then
    echo "[run] Installing bundled skill templates"
    rm -rf "$SKILL_TEMPLATES_DIR"
    mkdir -p "$SKILL_TEMPLATES_DIR"
    cp -R "$ADDON_SKILL_TEMPLATES_DIR"/. "$SKILL_TEMPLATES_DIR"/

    for template_skill_dir in "$SKILL_TEMPLATES_DIR"/*; do
        if [ ! -d "$template_skill_dir" ]; then
            continue
        fi

        skill_name="$(basename "$template_skill_dir")"
        active_skill_dir="$ACTIVE_SKILLS_DIR/$skill_name"
        template_skill_hash="$(compute_skill_hash "$template_skill_dir")"

        if [ -d "$active_skill_dir" ]; then
            active_skill_hash="$(compute_skill_hash "$active_skill_dir" 2>/dev/null || true)"
            if [ -n "$active_skill_hash" ] && [ "$active_skill_hash" != "$template_skill_hash" ]; then
                backup_path="$SKILL_BACKUP_DIR/${skill_name}-$(date +%Y%m%d-%H%M%S)"
                echo "[run] Backing up existing $skill_name skill to $backup_path"
                cp -R "$active_skill_dir" "$backup_path"
            fi
            rm -rf "$active_skill_dir"
        fi

        echo "[run] Syncing active $skill_name skill from bundled template"
        cp -R "$template_skill_dir" "$active_skill_dir"
        write_skill_sync_marker "$active_skill_dir" "$template_skill_hash"
    done

    if [ -d "$SKILL_TEMPLATES_DIR/$DEFAULT_SKILL_NAME" ]; then
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
    git -C "$SRC_DIR" fetch --tags origin
else
    echo "[run] Cloning Hermes Agent from $HERMES_REPO ($HERMES_REF)..."
    git clone "$HERMES_REPO" "$SRC_DIR"
fi

target_revision="$(resolve_hermes_ref || true)"
if [ -z "$target_revision" ]; then
    echo "[run] FATAL: Could not resolve Hermes ref $HERMES_REF from $HERMES_REPO"
    exit 1
fi
git -C "$SRC_DIR" reset --hard "$target_revision"
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
    OLLAMA_MODEL="$OLLAMA_MODEL" \
    HASS_TOKEN="$SUPERVISOR_TOKEN" \
    HASS_URL="http://supervisor/core" \
    TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
    TELEGRAM_ALLOWED_USERS="$TELEGRAM_ALLOWED_USERS" \
    MQTT_HOST="$MQTT_HOST" \
    MQTT_PORT="$MQTT_PORT" \
    MQTT_USER="$MQTT_USER" \
    MQTT_PASSWORD="$MQTT_PASSWORD" \
    API_SERVER_KEY="$ACCESS_PASSWORD" \
    hermes gateway run
