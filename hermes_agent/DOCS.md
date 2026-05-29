# Hermes Agent Add-on

Minimal Home Assistant add-on for running Hermes Agent in gateway mode.

This fork is stripped for small Home Assistant hosts such as a Raspberry Pi 4B. It runs one process only: `hermes gateway run`. There is no browser automation, no web terminal, no nginx proxy, and no bundled dashboard.

For the full development history of this fork, see [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md).

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `ollama_api_key` | | Ollama Cloud API key. Written to `/config/.hermes/.env` on every start. |
| `ollama_model` | `hermes3:latest` | Ollama Cloud model. Synced into the managed Hermes `ollama-cloud` model config on startup. |
| `telegram_bot_token` | | Telegram bot token. Written to `.env` when set. |
| `telegram_allowed_users` | | Comma-separated Telegram user IDs. Written to `.env` when set. |
| `mqtt_host` | `core-mosquitto` | MQTT broker host for Zigbee2MQTT. On HAOS with the Mosquitto add-on this is usually `core-mosquitto`. |
| `mqtt_port` | `1883` | MQTT broker port. |
| `mqtt_user` | | MQTT username. Written to `.env` and passed to Hermes when set. |
| `mqtt_password` | | MQTT password. Written to `.env` and passed to Hermes when set. |
| `access_password` | | Optional Hermes Gateway API key for external clients. |
| `auto_update` | `false` | When `false`, the add-on uses the pinned Hermes runtime revision shipped with this add-on release. When `true`, it tracks the runtime fork's `main` branch on startup. |

Home Assistant access uses the Supervisor token from the add-on environment. Do not configure or hardcode a Home Assistant token yourself.

## Runtime Behavior

On every start the add-on:

1. Reads the Home Assistant add-on options.
2. Ensures `/config/.hermes` exists.
3. Rewrites `/config/.hermes/.env` from the current options and `SUPERVISOR_TOKEN`.
4. Creates `/config/.hermes/config.yaml` if it does not already exist, or syncs the Ollama Cloud model value into an existing managed config.
5. Refreshes bundled skill templates under `/config/.hermes/skill-templates`.
6. Syncs all bundled skills into `/config/.hermes/skills`, backing up diverging active copies first.
7. Seeds `/config/.hermes/device_onboarding/known_devices.json` and its schema only if they do not already exist.
8. Clones or refreshes Hermes Agent in `/config/.hermes/hermes-agent` from `ohnesorgen2025-svg/hermes-agent`, using the pinned release revision unless `auto_update` is enabled.
9. Creates or reuses the Python virtual environment.
10. Installs Hermes Agent with the base editable install plus the Home Assistant/API, MQTT, and Telegram adapter dependencies.
11. Executes `hermes gateway run`.

The `.env` file is intentionally regenerated every start so Home Assistant option changes take effect. The Hermes `config.yaml` file is created on first run. On later starts, only the top-level `model.model` value is updated when the config still uses `provider: ollama-cloud`; custom configs using another provider are left unchanged.

Bundled skill templates are add-on managed and refreshed on update. The default active `device-onboarding` skill is synced from the bundled version on startup. If the active copy differs, the add-on saves a timestamped backup under `/config/.hermes/skill-backups/` before replacing it.

## First-Run Hermes Config

```yaml
model:
  provider: ollama-cloud
  model: "hermes3:latest"
platforms:
  homeassistant:
    enabled: true
  telegram:
    enabled: true
```

The model value follows the `ollama_model` add-on option. Changing the add-on option and restarting the add-on updates this value for managed Ollama Cloud configs.

## Bundled Skill Bootstrap

The add-on currently ships bundled skill templates for manual device onboarding, device identification, and Home Assistant administration.

Managed paths:

```text
/config/.hermes/skill-templates/device-onboarding/
/config/.hermes/skill-templates/device-identification/
/config/.hermes/skill-templates/home-assistant-admin/
/config/.hermes/skills/device-onboarding/
/config/.hermes/skills/device-identification/
/config/.hermes/skills/home-assistant-admin/
/config/.hermes/device_onboarding/known_devices.json
/config/.hermes/device_onboarding/known_devices.schema.json
```

Rules:

- `/config/.hermes/skill-templates/` contains managed reference copies refreshed by the add-on.
- `/config/.hermes/skills/` contains active bundled skills and is synced from the bundled templates on startup.
- If an active bundled skill differs from the bundled template, the add-on backs it up under `/config/.hermes/skill-backups/` before replacing it.
- The seeded `known_devices.json` starts empty so new installations do not inherit another installation's Zigbee device history.

## Bundled Device Identification Skill

The bundled `device-identification` skill identifies unknown physical devices from short Home Assistant event observation. Trigger phrases include `Lauschen`, `Welches Gerät ist das?`, `Gerät identifizieren`, and `Finde dieses Gerät`.

The skill tells the user to press, move, open, or switch the device, then calls:

```python
ha_observe_changes(duration_seconds=10)
```

The runtime tool listens to Home Assistant WebSocket `state_changed` events. It does not listen to audio. The default window is 10 seconds, with a hard maximum of 20 seconds. Results are scored so interactive transitions such as `off -> on`, `closed -> open`, button events, switches, and motion/contact sensors rank above routine telemetry such as battery, link-quality, temperature, humidity, weather, and system updates.

If a dimmer, remote, wall switch, or scene controller changes several lamps or switches in the same observation window, the observer marks the result as a cascade. It ranks likely controller/action entities above downstream actuator changes so Hermes can say that the lamp events are probably follow-up effects.

## Bundled Home Assistant Admin Skill

The bundled `home-assistant-admin` skill gives Hermes an explicit workflow for broad Home Assistant administration. It covers dashboards, Supervisor/add-ons, backups, Core/Supervisor/OS updates, Home Assistant `update.*` entities including HACS updates, integration config entries, repair issues, automations, entities, areas, Zigbee2MQTT, and Matter/Alexa exposure. The add-on declares Supervisor API access with admin role for these operations.

Read-only inspection does not require confirmation. Write, destructive, disruptive, or broad actions should be confirmed in chat first. After the user confirms, Hermes should execute the requested action without extra artificial hurdles. Dashboard writes create backups under `/config/.hermes/dashboard-backups/` where possible. Dashboard config saves use the Lovelace WebSocket API, while dashboard metadata such as title, icon, sidebar visibility, and admin-only access uses the Lovelace dashboard REST API.

## Generated Environment

```env
OLLAMA_API_KEY=<from add-on config>
OLLAMA_MODEL=<from add-on config>
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

The add-on does not install Home Assistant Core integrations. It checks and uses the integrations already configured in Home Assistant.

Onboarding preflight requirements:

| Flow | Required integrations/services |
| --- | --- |
| Zigbee | MQTT broker, Zigbee2MQTT, and the Home Assistant MQTT integration connected to the same broker. |
| Homematic | Home Assistant Homematic/HomematicIP Local integration with install-mode entities. |

If a requirement is missing, the bundled onboarding skill should stop before pairing and explain the missing setup step in German.

The runtime Hermes fork currently adds these Home Assistant-focused capabilities:

- entity list and state lookup
- service discovery and service calls
- automation management through Home Assistant automation WebSocket config commands, with REST fallback
- Lovelace dashboard administration through Home Assistant WebSocket commands and Lovelace dashboard REST metadata endpoints
- Supervisor/add-on/update/backup/log management through the Home Assistant Supervisor API
- Home Assistant update entity management through `update.install`, including HACS update entities when HACS exposes them
- integration config-entry and repair inspection through Home Assistant WebSocket commands
- entity rename through the Home Assistant entity registry WebSocket API, including `new_entity_id` and optional area assignment
- Zigbee2MQTT management over MQTT
- Matter/Alexa exposure management through the Home Assistant entity registry label `matter`
- short Home Assistant event observation through `ha_observe_changes` for identifying recently triggered physical devices

The bundled `device-onboarding` skill builds on these native Hermes capabilities but also carries skill-specific orchestration logic such as room choice prompts, naming suggestions, and `known_devices.json`-based diffing.

Matter exposure actions exposed through Hermes:

| Action | Purpose |
| --- | --- |
| `expose` | Adds the `matter` label to an entity so Home Assistant Matter Hub can expose it. |
| `unexpose` | Removes the `matter` label from an entity. |
| `list_exposed` | Lists entities currently labeled with `matter`. |

`expose` and `unexpose` use the Home Assistant WebSocket API commands `config/entity_registry/get` and `config/entity_registry/update`. The entity registry has no REST API for these label writes. `list_exposed` uses the Home Assistant template endpoint with `label_entities('matter')`.

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

By default, this add-on release pins the Hermes runtime source to:

```text
33a5bf64ce058b6cc6f5d4df4d7f042873d405c1
```

Set `auto_update: true` only when you intentionally want the add-on to track the runtime fork's `main` branch on startup. Advanced test builds can override the runtime checkout with `HERMES_REF`, which accepts a branch, tag, or commit hash.

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
|-- config.yaml        # Created on first run; Ollama Cloud model synced on start
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

If Matter/Alexa exposure changes fail, check that the entity exists in the Home Assistant entity registry and that the Home Assistant Matter Hub label ID is `matter`. Entity label updates are performed through the Home Assistant WebSocket API, not REST.

To force a clean Hermes reinstall, stop the add-on and remove `/config/.hermes/hermes-agent`. Keep `/config/.hermes/config.yaml` if you want to preserve manual Hermes configuration edits.

If you customized the active `device-onboarding` skill, check `/config/.hermes/skill-backups/` after an add-on update and reapply any local changes you still need.
