# Hermes Agent Add-on

Minimal Home Assistant add-on for running Hermes Agent in gateway mode.

This fork is stripped for small Home Assistant hosts such as a Raspberry Pi 4B. It runs one process only: `hermes gateway run`. There is no browser automation, no web terminal, no nginx proxy, and no bundled dashboard.

For the full development history of this fork, see [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md).

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `ollama_api_key` | | Ollama Cloud API key. Written to `/config/.hermes/.env` on every start. |
| `ollama_model` | `hermes3:latest` | Ollama Cloud model used in the first-run Hermes config. |
| `telegram_bot_token` | | Telegram bot token. Written to `.env` when set. |
| `telegram_allowed_users` | | Comma-separated Telegram user IDs. Written to `.env` when set. |
| `mqtt_host` | `core-mosquitto` | MQTT broker host for Zigbee2MQTT. On HAOS with the Mosquitto add-on this is usually `core-mosquitto`. |
| `mqtt_port` | `1883` | MQTT broker port. |
| `mqtt_user` | | MQTT username. Written to `.env` and passed to Hermes when set. |
| `mqtt_password` | | MQTT password. Written to `.env` and passed to Hermes when set. |
| `access_password` | | Optional Hermes Gateway API key for external clients. |
| `auto_update` | `false` | Compatibility option; the Hermes source is refreshed from the configured fork on add-on start. |

Home Assistant access uses the Supervisor token from the add-on environment. Do not configure or hardcode a Home Assistant token yourself.

## Runtime Behavior

On every start the add-on:

1. Reads the Home Assistant add-on options.
2. Ensures `/config/.hermes` exists.
3. Rewrites `/config/.hermes/.env` from the current options and `SUPERVISOR_TOKEN`.
4. Creates `/config/.hermes/config.yaml` only if it does not already exist.
5. Clones or refreshes Hermes Agent in `/config/.hermes/hermes-agent` from `ohnesorgen2025-svg/hermes-agent`.
6. Creates or reuses the Python virtual environment.
7. Installs Hermes Agent with the base editable install plus the Home Assistant/API, MQTT, and Telegram adapter dependencies.
8. Executes `hermes gateway run`.

The `.env` file is intentionally regenerated every start so Home Assistant option changes take effect. The Hermes `config.yaml` file is intentionally first-run only so manual user edits are preserved.

## First-Run Hermes Config

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

The generated model value follows the `ollama_model` add-on option.

## Generated Environment

```env
OLLAMA_API_KEY=<from add-on config>
HASS_TOKEN=<SUPERVISOR_TOKEN>
HASS_URL=http://supervisor/core
TELEGRAM_BOT_TOKEN=<from add-on config, when set>
TELEGRAM_ALLOWED_USERS=<from add-on config, when set>
MQTT_HOST=<from add-on config>
MQTT_PORT=<from add-on config>
MQTT_USER=<from add-on config, when set>
MQTT_PASSWORD=<from add-on config, when set>
API_SERVER_KEY=<access_password, when set>
```

The same values are also passed directly to the Hermes process with `exec env`, so `os.getenv(...)` in Hermes sees the add-on configuration. On startup the add-on log prints a secretsafe MQTT diagnostic line:

```text
[run] MQTT config: host=core-mosquitto port=1883 user_set=yes password_set=yes
```

The password value is never logged.

## Home Assistant Tools

The runtime Hermes fork currently adds these Home Assistant-focused capabilities:

- entity list and state lookup
- service discovery and service calls
- automation management through Home Assistant config REST endpoints
- entity rename through the Home Assistant entity registry API
- Zigbee2MQTT management over MQTT

Zigbee2MQTT actions exposed through Hermes:

| Action | Purpose |
| --- | --- |
| `permit_join` | Opens Zigbee pairing for a limited duration. Maximum duration is 254 seconds. |
| `list_devices` | Reads retained Zigbee2MQTT bridge device information. |
| `rename_device` | Renames a Zigbee2MQTT device friendly name. |
| `remove_device` | Removes a device by explicit IEEE address. Wildcards are not allowed. |

## Zigbee2MQTT Setup

For Home Assistant entities to appear after pairing a Zigbee device, configure all of these layers:

1. Mosquitto broker add-on is installed and running.
2. Zigbee2MQTT add-on is installed, connected to Mosquitto, and has Home Assistant discovery enabled.
3. This Hermes add-on has matching `mqtt_host`, `mqtt_port`, `mqtt_user`, and `mqtt_password` options.
4. Home Assistant Core has the MQTT integration installed and connected to the same Mosquitto broker.

The Mosquitto add-on and Zigbee2MQTT add-on do not automatically create Home Assistant entities by themselves. Home Assistant Core must have the MQTT integration so it subscribes to retained discovery topics such as:

```text
homeassistant/sensor/<ieee>/temperature/config
```

On HAOS with the Mosquitto add-on, use this broker host in both Hermes and the Home Assistant MQTT integration:

```text
core-mosquitto
```

## Updates

Home Assistant sees add-on updates through the `version` field in `config.yaml`. Bump that version whenever a new add-on release should appear in Home Assistant.

The add-on repository and Hermes source repository are separate:

```text
Add-on package:  https://github.com/ohnesorgen2025-svg/hermes-ha-addon
Hermes source:   https://github.com/ohnesorgen2025-svg/hermes-agent
```

An update on an existing Home Assistant instance keeps `/config/.hermes` in place. The entrypoint only updates the managed source clone at `/config/.hermes/hermes-agent`; it does not delete user configuration, memories, sessions, skills, or `state.db`.

A fresh install on another Home Assistant instance starts with a fresh `/config/.hermes` directory and its own configuration.

## Persistence

All Hermes data lives under `/config/.hermes` and survives add-on restarts and updates:

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

## What Is Not Included

This slim add-on intentionally does not include:

- nginx or Home Assistant ingress UI
- ttyd or tmux web terminals
- Chromium, Playwright, or agent-browser
- WhatsApp/Puppeteer bridge
- Homebrew or Go toolchain
- bundled editor and diagnostic tools such as `vim`, `nano`, `htop`, `gh`, `bat`, `fd-find`, ImageMagick, or Ghostscript

Hermes is installed without the `[all]` extra. Home Assistant/API support is added through `aiohttp`; Zigbee2MQTT support is added through `paho-mqtt`; Telegram support is added through the narrow `python-telegram-bot[webhooks]` dependency.

## Troubleshooting

If Hermes does not start, check the add-on log first. Common causes are a missing Ollama Cloud API key, an invalid Telegram bot token, or upstream Hermes dependency changes during install.

For MQTT/Zigbee2MQTT issues, check the startup diagnostic line in the add-on log:

```text
[run] MQTT config: host=... port=... user_set=yes/no password_set=yes/no
```

If Hermes uses `localhost:1883`, the saved add-on option is still `localhost`; change `mqtt_host` to `core-mosquitto` for the Mosquitto add-on on HAOS. Existing Home Assistant add-on installations keep saved option values when defaults change.

If Zigbee devices pair in Zigbee2MQTT but no Home Assistant entities appear, verify that Home Assistant Core has the MQTT integration configured. The MQTT add-on/broker and Zigbee2MQTT add-on are separate from the Home Assistant MQTT integration.

To force a clean Hermes reinstall, stop the add-on and remove `/config/.hermes/hermes-agent`. Keep `/config/.hermes/config.yaml` if you want to preserve manual Hermes configuration edits.
