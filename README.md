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
- Ships bundled skill templates and installs a default `device-onboarding` skill on fresh instances
- Ships a bundled `device-identification` skill that can identify touched devices from short Home Assistant event observation
- Ships a bundled `home-assistant-admin` skill for dashboard, add-on, update, backup, and integration administration
- Keeps the Hermes git clone and Python venv in persistent storage
- Refreshes the Hermes source clone from `ohnesorgen2025-svg/hermes-agent` to a pinned revision by default
- Installs Hermes without `[all]`, adding only the Home Assistant/API, MQTT, and Telegram adapter dependencies
- Exposes Hermes tools for Home Assistant automation management, dashboard administration, Supervisor/add-on administration, integration inspection, entity rename, Zigbee2MQTT device management, Matter/Alexa label exposure, and short state-change observation

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
| `ollama_model` | `hermes3:latest` | Ollama Cloud model. Synced into the managed Hermes `ollama-cloud` model config on startup. |
| `telegram_bot_token` | | Telegram bot token. |
| `telegram_allowed_users` | | Comma-separated Telegram user IDs allowed to use the bot. |
| `mqtt_host` | `core-mosquitto` | MQTT broker host. On HAOS with the Mosquitto add-on this is usually `core-mosquitto`. |
| `mqtt_port` | `1883` | MQTT broker port. |
| `mqtt_user` | | MQTT username for Mosquitto/Zigbee2MQTT. |
| `mqtt_password` | | MQTT password for Mosquitto/Zigbee2MQTT. |
| `access_password` | | Optional Hermes Gateway API key for external clients. |
| `auto_update` | `false` | When `false`, the add-on uses the pinned Hermes runtime revision shipped with this add-on release. When `true`, it tracks the runtime fork's `main` branch on startup. |

Home Assistant authentication is provided by the add-on `SUPERVISOR_TOKEN` environment variable. This fork does not accept a manually configured Home Assistant token.

## Generated Files

On every start, the add-on rewrites `/config/.hermes/.env`:

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

The entrypoint also passes these values directly to `hermes gateway run` with `exec env`. The add-on log prints a secretsafe MQTT summary on startup:

```text
[run] MQTT config: host=core-mosquitto port=1883 user_set=yes password_set=yes
```

On first start, the add-on creates `/config/.hermes/config.yaml`:

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

The model name follows the `ollama_model` add-on option. On later starts, the add-on updates only the top-level `model.model` value when the existing Hermes config still uses `provider: ollama-cloud`. Custom configs using another provider are left unchanged.

## Bundled Device Onboarding Skill

This add-on now ships a bundled `device-onboarding` skill template for Zigbee onboarding.

Bootstrap behavior:

- On every start, the add-on refreshes the managed reference copy under `/config/.hermes/skill-templates/device-onboarding`.
- On a fresh Home Assistant instance, if `/config/.hermes/skills/device-onboarding` does not exist yet, the add-on installs that skill as the active default skill.
- On an existing instance, the active `device-onboarding` skill is refreshed from the bundled version on startup.
- If the active `device-onboarding` skill differs from the bundled version, the add-on first backs it up under `/config/.hermes/skill-backups/` and then installs the current bundled copy.
- The add-on also seeds `/config/.hermes/device_onboarding/known_devices.json` and its schema if they do not already exist.

The bundled skill is currently a Zigbee-focused, manually triggered onboarding flow. It uses Hermes `clarify`, `ha_zigbee_manage`, and `ha_matter_manage` primitives and keeps device tracking in `known_devices.json`.

## Bundled Device Identification Skill

This add-on also ships a `device-identification` skill for unknown physical devices. In Telegram, say `Lauschen`, `Welches Gerät ist das?`, or `Gerät identifizieren`. Hermes then observes Home Assistant `state_changed` events for 10 seconds and asks you to press, move, open, or switch the physical device.

The skill uses the runtime `ha_observe_changes` tool. It listens to Home Assistant events, not audio. The short default window reduces background noise from routine temperature, battery, link-quality, weather, and system updates. The tool scores interactive changes such as button presses, contact sensor transitions, switch changes, and motion events higher than periodic telemetry. If one dimmer, remote, or wall switch triggers many lamps at once, the observer treats that as a cascade and ranks likely controller/action entities above downstream lamp changes.

## Bundled Home Assistant Admin Skill

This add-on ships a `home-assistant-admin` skill for broad Home Assistant administration. Hermes can inspect and manage Lovelace dashboards, Supervisor/add-ons, backups, Core/Supervisor/OS updates, Home Assistant `update.*` entities including HACS updates, integration config entries, repair issues, automations, entities, areas, Zigbee2MQTT, and Matter/Alexa exposure. The add-on declares Supervisor API access with admin role for these operations and includes read-only admin diagnosis for API-path and permission problems.

Read-only inspection can run directly. Write, destructive, disruptive, or broad actions should be confirmed in chat first. After confirmation, Hermes is expected to execute without extra artificial hurdles. Dashboard writes create JSON backups under `/config/.hermes/dashboard-backups/` where possible. Dashboard config is saved through the Lovelace WebSocket API; dashboard metadata such as title, icon, sidebar visibility, and admin-only access is updated through the Lovelace dashboard REST API.

## Home Assistant and Zigbee2MQTT

The add-on does not install Home Assistant Core integrations. It checks and uses them. Device onboarding expects the required integrations to be present in Home Assistant before pairing starts.

Preflight checks for onboarding:

| Flow | Must already be configured in Home Assistant |
| --- | --- |
| Zigbee | Mosquitto or another MQTT broker, Zigbee2MQTT connected to that broker, and the Home Assistant MQTT integration connected to the same broker. |
| Homematic | The Home Assistant Homematic/HomematicIP Local integration with visible install-mode entities. |

If a prerequisite is missing, the bundled onboarding skill should stop before pairing and tell the user what to configure first.

The runtime Hermes fork includes Home Assistant tools for:

- listing entities and reading states
- listing and calling Home Assistant services
- creating, updating, deleting, listing, and reading full automation configs including triggers, conditions, and actions
- creating, reading, saving, and editing Lovelace dashboards
- managing Home Assistant Supervisor, add-ons, updates, logs, and backups
- installing Home Assistant `update.*` entities, including HACS-managed integrations and frontend resources when HACS exposes update entities
- diagnosing Home Assistant admin API capabilities and classifying failures before falling back to manual instructions
- inspecting integration config entries and repair issues, and reloading/removing entries where HA permits it
- renaming Home Assistant entities
- managing Zigbee2MQTT over MQTT: permit join, list devices, rename devices, and remove devices
- exposing or unexposing Home Assistant entities for Home Assistant Matter Hub by adding or removing the `matter` entity label
- observing Home Assistant state changes for a short window to identify a physical device the user just triggered

## Matter Hub and Alexa Exposure

The runtime Hermes fork includes `ha_matter_manage` for controlling which Home Assistant entities are exposed through Home Assistant Matter Hub, for example to Alexa.

Supported actions:

| Action | Purpose |
| --- | --- |
| `expose` | Adds the `matter` label to a Home Assistant entity. |
| `unexpose` | Removes the `matter` label from a Home Assistant entity. |
| `list_exposed` | Lists entities currently carrying the `matter` label. |

`expose` and `unexpose` use the Home Assistant WebSocket API because the entity registry does not provide REST endpoints for label updates. `list_exposed` uses the Home Assistant template endpoint with `label_entities('matter')`.

Home Assistant Matter Hub watches the `matter` label and updates the exposed Matter device set from Home Assistant. The label ID must be `matter`.

For Zigbee2MQTT device discovery in Home Assistant, all three pieces must be configured:

1. Mosquitto broker add-on running.
2. Zigbee2MQTT add-on connected to Mosquitto with Home Assistant discovery enabled.
3. Home Assistant MQTT integration configured and connected to the same broker.

The Mosquitto add-on alone does not create Home Assistant entities. Home Assistant Core needs the MQTT integration so it subscribes to retained discovery topics under `homeassistant/#`.

This fork was verified end-to-end with an ONENUO TH05Z / Tuya TS0601 temperature and humidity sensor. Hermes enabled Zigbee pairing, Zigbee2MQTT paired and renamed the device to `klima.wohnzimmer`, and Home Assistant created the MQTT device with 15 entities after the MQTT integration was configured.

## Persistent Storage

```text
/config/.hermes/
|-- hermes-agent/      # Hermes source clone and venv
|-- memories/          # Long-term memory
|-- sessions/          # Conversation state
|-- skills/            # Hermes skills
|-- skill-templates/   # Add-on managed reference skills
|-- device_onboarding/ # Bundled onboarding skill data
|-- .env               # Regenerated on every start
|-- config.yaml        # Created on first run; Ollama Cloud model synced on start
`-- state.db           # Hermes state database
```

## Updates

This repository is the Home Assistant add-on update channel. Home Assistant detects updates through the `version` field in `hermes_agent/config.yaml`.

The runtime Hermes source comes from a separate fork:

```text
https://github.com/ohnesorgen2025-svg/hermes-agent.git
```

On add-on start, `run.sh` updates the managed source clone at `/config/.hermes/hermes-agent` to the runtime revision pinned by this add-on release. If `auto_update` is enabled, it tracks `origin/main` instead. If the clone does not exist, it is created fresh. If it already exists, only the managed source clone is reset; user data outside that clone is left alone.

The default pinned Hermes runtime revision for this release is:

```text
35b520ed3165e74ebddb047061776f4d2b06740a
```

Existing Home Assistant instance:

1. Build or merge a feature into `ohnesorgen2025-svg/hermes-agent`.
2. Bump the add-on `version` in `hermes_agent/config.yaml`.
3. Push `ohnesorgen2025-svg/hermes-ha-addon`.
4. Home Assistant offers an add-on update.
5. Updating keeps `/config/.hermes/config.yaml`, memories, sessions, active skills, and state intact.
6. The add-on refreshes managed reference templates under `/config/.hermes/skill-templates/` and syncs the active `device-onboarding` skill from the bundled copy.
7. If the active `device-onboarding` skill had local changes, the add-on saves a timestamped backup under `/config/.hermes/skill-backups/` before replacing it.

New Home Assistant instance:

1. Install this add-on repository.
2. Configure fresh Ollama and Telegram values.
3. A new `/config/.hermes` directory is created for that instance.
4. The bundled `device-onboarding` skill is installed automatically as the default active skill.

## Development History

The complete development record from fork cleanup through Zigbee2MQTT end-to-end validation is documented in [hermes_agent/DEVELOPMENT_LOG.md](hermes_agent/DEVELOPMENT_LOG.md).

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