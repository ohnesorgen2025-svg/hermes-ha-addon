# Hermes Agent Home Assistant Add-on Slim

Fork of [WolframRavenwolf/hermes-ha-addon](https://github.com/WolframRavenwolf/hermes-ha-addon), stripped down for running [Hermes Agent](https://hermes-agent.nousresearch.com/) as a Home Assistant gateway on small hardware.

The target setup is a Raspberry Pi 4B with Home Assistant, Ollama Cloud as the model provider, Telegram for messaging, and Home Assistant control via the Supervisor token.

## What This Fork Does

- Runs one process: `hermes gateway run`
- Uses Ollama Cloud by default
- Enables Home Assistant and Telegram platforms in the first-run Hermes config
- Stores all Hermes data in `/config/.hermes`
- Rewrites `/config/.hermes/.env` on every start from the add-on options
- Creates `/config/.hermes/config.yaml` only if it does not already exist
- Keeps the Hermes git clone and Python venv in persistent storage
- Refreshes the Hermes source clone from `ohnesorgen2025-svg/hermes-agent`
- Installs Hermes without `[all]`, adding only the Home Assistant/API and Telegram adapter dependencies

## What Was Removed

- nginx and Home Assistant ingress UI
- ttyd web terminal and tmux session management
- Chromium, Playwright, and agent-browser
- WhatsApp/Puppeteer bridge
- Homebrew and Go toolchain
- bundled editor and diagnostic tools such as `vim`, `nano`, `htop`, `gh`, `bat`, `fd-find`, ImageMagick, and Ghostscript

## Installation

1. In Home Assistant, open **Settings > Add-ons > Add-on Store**.
2. Open the menu and choose **Repositories**.
3. Add this fork URL.
4. Install **Hermes Agent**.
5. Configure Ollama Cloud and Telegram options.
6. Start the add-on and watch the add-on log.

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `ollama_api_key` | | Ollama Cloud API key. |
| `ollama_model` | `hermes3:latest` | Ollama Cloud model for first-run config generation. |
| `telegram_bot_token` | | Telegram bot token. |
| `telegram_allowed_users` | | Comma-separated Telegram user IDs allowed to use the bot. |
| `access_password` | | Optional Hermes Gateway API key for external clients. |
| `auto_update` | `false` | Compatibility option; the Hermes source is refreshed from the configured fork on add-on start. |

Home Assistant authentication is provided by the add-on `SUPERVISOR_TOKEN` environment variable. This fork does not accept a manually configured Home Assistant token.

## Generated Files

On every start, the add-on rewrites `/config/.hermes/.env`:

```env
OLLAMA_API_KEY=<from add-on config>
HASS_TOKEN=<SUPERVISOR_TOKEN>
HASS_URL=http://supervisor/core
TELEGRAM_BOT_TOKEN=<from add-on config, when set>
TELEGRAM_ALLOWED_USERS=<from add-on config, when set>
API_SERVER_KEY=<access_password, when set>
```

On first start only, the add-on creates `/config/.hermes/config.yaml`:

```yaml
model:
  provider: ollama-cloud
  model: hermes3:latest
platforms:
  homeassistant:
    enabled: true
  telegram:
    enabled: true
```

The generated model name follows the `ollama_model` add-on option. Existing `config.yaml` files are never overwritten by the add-on.

## Persistent Storage

```text
/config/.hermes/
|-- hermes-agent/      # Hermes source clone and venv
|-- memories/          # Long-term memory
|-- sessions/          # Conversation state
|-- skills/            # Hermes skills
|-- .env               # Regenerated on every start
|-- config.yaml        # Created only on first run
`-- state.db           # Hermes state database
```

## Updates

This repository is the Home Assistant add-on update channel. Home Assistant detects updates through the `version` field in `hermes_agent/config.yaml`.

The runtime Hermes source comes from a separate fork:

```text
https://github.com/ohnesorgen2025-svg/hermes-agent.git
```

On add-on start, `run.sh` updates the managed source clone at `/config/.hermes/hermes-agent` to `origin/main` from that fork. If the clone does not exist, it is created fresh. If it already exists, only the managed source clone is reset; user data outside that clone is left alone.

Existing Home Assistant instance:

1. Build or merge a feature into `ohnesorgen2025-svg/hermes-agent`.
2. Bump the add-on `version` in `hermes_agent/config.yaml`.
3. Push `ohnesorgen2025-svg/hermes-ha-addon`.
4. Home Assistant offers an add-on update.
5. Updating keeps `/config/.hermes/config.yaml`, memories, sessions, skills, and state intact.

New Home Assistant instance:

1. Install this add-on repository.
2. Configure fresh Ollama and Telegram values.
3. A new `/config/.hermes` directory is created for that instance.

## Local Build Test

```bash
cd hermes_agent
docker build \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm \
  -t hermes-ha-addon-slim .
docker run -it --rm \
  -e SUPERVISOR_TOKEN=test \
  -v $(pwd)/test-config:/config \
  hermes-ha-addon-slim
docker images hermes-ha-addon-slim
```

## Architectures

- `amd64`
- `aarch64`

## License

This add-on fork is MIT licensed. Hermes Agent itself is MIT licensed by Nous Research.