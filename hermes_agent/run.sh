#!/command/with-contenv bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
HERMES_REPO="${HERMES_REPO:-https://github.com/ohnesorgen2025-svg/hermes-agent.git}"
PINNED_HERMES_REF="${PINNED_HERMES_REF:-cf2f6a1f2c324ca9e39bf748a88ee6faa73a4adb}"
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
SYNC_SCRIPTS_DIR="/opt/hermes-addon/scripts"
SKILL_SYNC_LOG_DIR="$HERMES_HOME/logs"
SKILL_SYNC_LOG_FILE="$SKILL_SYNC_LOG_DIR/skill-sync.log"
SKILL_SYNC_CRON_SCHEDULE="${HERMES_STATE_SYNC_CRON:-17 3 * * *}"

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

start_skill_sync_cron() {
    if [ ! -x "$SYNC_SCRIPTS_DIR/sync-skills.sh" ]; then
        echo "[run] WARN: $SYNC_SCRIPTS_DIR/sync-skills.sh not found; skill sync cron disabled"
        return
    fi

    mkdir -p "$SKILL_SYNC_LOG_DIR"
    touch "$SKILL_SYNC_LOG_FILE"
    chmod 600 "$SKILL_SYNC_LOG_FILE"

    cat > /etc/cron.d/hermes-skill-sync <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOME=/config
${SKILL_SYNC_CRON_SCHEDULE} root ${SYNC_SCRIPTS_DIR}/sync-skills.sh >> ${SKILL_SYNC_LOG_FILE} 2>&1
EOF
    chmod 0644 /etc/cron.d/hermes-skill-sync

    echo "[run] Starting daily skill sync cron ($SKILL_SYNC_CRON_SCHEDULE)"
    cron
}

sync_managed_model_config() {
    local config_file="$1"
    local provider_name="$2"
    local model_name="$3"
    local base_url="${4:-}"

    python3 - "$config_file" "$provider_name" "$model_name" "$base_url" << 'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
provider_name = sys.argv[2]
model_name = sys.argv[3]
base_url = sys.argv[4] if len(sys.argv) > 4 else ""
lines = path.read_text(encoding="utf-8").splitlines()

# The add-on is the source of truth for the model section. Selecting the
# special provider "manual" (or leaving it empty) tells the add-on to keep
# its hands off so advanced users can hand-edit the Hermes config.
if provider_name.strip().lower() in {"", "manual"}:
    sys.exit(0)

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

provider_index = None
model_index = None
base_url_index = None
indent = "    "
for index in range(start + 1, end):
    if lines[index].lstrip() != lines[index] and lines[index].strip().startswith("provider:"):
        provider_index = index
        indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
    if lines[index].lstrip() != lines[index] and lines[index].strip().startswith("model:"):
        model_index = index
        indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
    if lines[index].lstrip() != lines[index] and lines[index].strip().startswith("base_url:"):
        base_url_index = index
        indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]

escaped_provider = provider_name.replace('\\', '\\\\').replace('"', '\\"')
escaped_model = model_name.replace('\\', '\\\\').replace('"', '\\"')
escaped_base_url = base_url.replace('\\', '\\\\').replace('"', '\\"')
provider_line = f'{indent}provider: {escaped_provider}'
model_line = f'{indent}model: "{escaped_model}"'
base_url_line = f'{indent}base_url: "{escaped_base_url}"'
changed = False

if provider_index is None:
    lines.insert(start + 1, provider_line)
    end += 1
    changed = True
elif lines[provider_index] != provider_line:
    lines[provider_index] = provider_line
    changed = True

if model_index is None:
    insert_at = start + 1
    for index in range(start + 1, end):
        if lines[index].strip().startswith("provider:"):
            insert_at = index + 1
            indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
            model_line = f'{indent}model: "{escaped_model}"'
            break
    lines.insert(insert_at, model_line)
    changed = True
else:
    if lines[model_index] != model_line:
        lines[model_index] = model_line
        changed = True

# Only manage base_url when the add-on supplies one. An empty option leaves
# any existing line untouched so it can still be hand-edited in "manual" mode.
if base_url:
    if base_url_index is None:
        insert_at = start + 1
        for index in range(start + 1, len(lines)):
            if lines[index].strip().startswith("model:") and lines[index].lstrip() != lines[index]:
                insert_at = index + 1
                indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
                base_url_line = f'{indent}base_url: "{escaped_base_url}"'
                break
        lines.insert(insert_at, base_url_line)
        changed = True
    elif lines[base_url_index] != base_url_line:
        lines[base_url_index] = base_url_line
        changed = True

if not changed:
    sys.exit(0)

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

DEFAULT_PROVIDER="$(config_value default_provider "ollama-cloud")"
DEFAULT_API_KEY="$(config_value default_api_key "")"
DEFAULT_MODEL="$(config_value default_model "")"
MODEL_BASE_URL="$(config_value model_base_url "")"
TELEGRAM_BOT_TOKEN="$(config_value telegram_bot_token "")"
TELEGRAM_ALLOWED_USERS="$(config_value telegram_allowed_users "")"
MQTT_HOST="$(config_value mqtt_host "core-mosquitto")"
MQTT_PORT="$(config_value mqtt_port "1883")"
MQTT_USER="$(config_value mqtt_user "")"
MQTT_PASSWORD="$(config_value mqtt_password "")"
ACCESS_PASSWORD="$(config_value access_password "")"
AUTO_UPDATE="$(config_bool auto_update)"

HERMES_MODEL_PROVIDER="$DEFAULT_PROVIDER"
HERMES_MODEL_NAME="${DEFAULT_MODEL:-hermes3:latest}"

# Map a provider id to the exact environment variable Hermes expects for its
# API key, so the user only picks a provider and pastes a key — never needing
# to know variable names. Empty = no single managed key (manual).
provider_api_key_var() {
    case "$1" in
        ollama-cloud) printf 'OLLAMA_API_KEY' ;;
        openrouter)   printf 'OPENROUTER_API_KEY' ;;
        deepseek)     printf 'DEEPSEEK_API_KEY' ;;
        xai)          printf 'XAI_API_KEY' ;;
        anthropic)    printf 'ANTHROPIC_API_KEY' ;;
        gemini)       printf 'GEMINI_API_KEY' ;;
        zai)          printf 'GLM_API_KEY' ;;
        nvidia)       printf 'NVIDIA_API_KEY' ;;
        huggingface)  printf 'HF_TOKEN' ;;
        custom)       printf 'OPENAI_API_KEY' ;;
        *)            printf '' ;;
    esac
}

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
write_env_var "MODEL_PROVIDER" "$HERMES_MODEL_PROVIDER"
write_env_var "HERMES_MODEL" "$HERMES_MODEL_NAME"
if [ -n "$MODEL_BASE_URL" ]; then
    write_env_var "MODEL_BASE_URL" "$MODEL_BASE_URL"
fi

# Helper: store one provider's API key under its mapped variable.
set_provider_key() {
    local prov="$1"
    local key="$2"
    [ -z "$key" ] && return 0
    local var
    var="$(provider_api_key_var "$prov")"
    if [ -z "$var" ]; then
        echo "[run] WARN: provider '$prov' has no managed key variable; key ignored"
        return 0
    fi
    write_env_var "$var" "$key"
    export "$var=$key"
    echo "[run] Key for '$prov' set via $var"
}

# 1) Start/default provider key (bottom section of the options form).
set_provider_key "$DEFAULT_PROVIDER" "$DEFAULT_API_KEY"

# 2) Extra providers added via the repeatable "providers" list (Add button).
#    Each entry is {provider, api_key}; the key is stored under the provider's
#    mapped variable so it appears in the Telegram /model picker.
CONFIGURED_PROVIDERS=()
if [ -f "$OPTIONS_FILE" ]; then
    while IFS=$'\t' read -r p_provider p_key; do
        [ -z "$p_provider" ] && continue
        set_provider_key "$p_provider" "$p_key"
        CONFIGURED_PROVIDERS+=("$p_provider")
    done < <(jq -r '.providers[]? | [.provider // "", .api_key // ""] | @tsv' "$OPTIONS_FILE")
fi
if [ "${#CONFIGURED_PROVIDERS[@]}" -gt 0 ]; then
    echo "[run] Extra providers configured: ${CONFIGURED_PROVIDERS[*]}"
fi
write_env_var "HASS_TOKEN" "$SUPERVISOR_TOKEN"
write_env_var "HASS_URL" "http://supervisor/core"
write_env_var "HA_CONFIG_DIR" "/homeassistant"
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

export MODEL_PROVIDER="$HERMES_MODEL_PROVIDER"
export HERMES_MODEL="$HERMES_MODEL_NAME"
if [ -n "$MODEL_BASE_URL" ]; then
    export MODEL_BASE_URL
fi
export HASS_TOKEN="$SUPERVISOR_TOKEN"
export HASS_URL="http://supervisor/core"
export HA_CONFIG_DIR="/homeassistant"
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
        {
            echo "model:"
            echo "    provider: ${HERMES_MODEL_PROVIDER}"
            echo "    model: \"${HERMES_MODEL_NAME}\""
            if [ -n "$MODEL_BASE_URL" ]; then
                echo "    base_url: \"${MODEL_BASE_URL}\""
            fi
            cat << 'EOF'
platforms:
    homeassistant:
        enabled: true
    telegram:
        enabled: true
EOF
        } > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
else
    echo "[run] Syncing model setting into existing Hermes config when managed"
    sync_managed_model_config "$CONFIG_FILE" "$HERMES_MODEL_PROVIDER" "$HERMES_MODEL_NAME" "$MODEL_BASE_URL"
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
start_skill_sync_cron
exec env \
    MODEL_PROVIDER="$HERMES_MODEL_PROVIDER" \
    HERMES_MODEL="$HERMES_MODEL_NAME" \
    HASS_TOKEN="$SUPERVISOR_TOKEN" \
    HASS_URL="http://supervisor/core" \
    HA_CONFIG_DIR="/homeassistant" \
    TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
    TELEGRAM_ALLOWED_USERS="$TELEGRAM_ALLOWED_USERS" \
    MQTT_HOST="$MQTT_HOST" \
    MQTT_PORT="$MQTT_PORT" \
    MQTT_USER="$MQTT_USER" \
    MQTT_PASSWORD="$MQTT_PASSWORD" \
    API_SERVER_KEY="$ACCESS_PASSWORD" \
    hermes gateway run
