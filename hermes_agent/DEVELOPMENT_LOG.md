# Development Log

This document records the evolution of this slim Home Assistant add-on fork from the original `WolframRavenwolf/hermes-ha-addon` into the current Raspberry Pi focused gateway build.

## Starting Point

The repository started as a fork of `WolframRavenwolf/hermes-ha-addon`. The original add-on provided a broader Hermes runtime with browser tooling, terminal access, nginx ingress support, dashboard/landing UI assets, and a larger system package set.

The target changed to a small, stable Home Assistant gateway setup for a Raspberry Pi 4B with 4 GB RAM:

- Hermes gateway mode only
- Ollama Cloud as model provider
- Telegram as messaging interface
- Home Assistant integration through the Supervisor token
- No browser automation
- No web terminal
- No nginx reverse proxy
- No WhatsApp/Puppeteer bridge
- Minimal runtime dependencies

## Phase 1: Strip Bloat

Commit: `d2ab56b feat: strip bloat — remove browser, terminal, nginx`

Major removals:

- Removed nginx config/templates and ingress UI pieces.
- Removed ttyd web terminal and tmux/session management.
- Removed landing/loading HTML UI assets.
- Removed Chromium, Playwright, and agent-browser installation paths.
- Removed WhatsApp/Puppeteer bridge support.
- Removed Homebrew and Go toolchain installation.
- Removed bundled operator tools that are not needed for Hermes gateway operation, including editor/debug/image utilities.

Dockerfile direction:

- Kept Python, Node.js, uv, git, curl, jq, ffmpeg, sqlite, and ripgrep.
- Removed broad development/tooling packages.
- Avoided Hermes `[all]` installs.

Configuration direction:

- Simplified Home Assistant add-on options toward Ollama Cloud, Telegram, access password, and update behavior.
- Preserved the add-on slug `hermes_agent`.
- Preserved the persistent Hermes home path `/config/.hermes`.

## Phase 2: Minimal Runtime Entrypoint

Commit: `4721a1d feat: minimal run.sh with ollama-cloud + telegram`

`run.sh` was rewritten around one process:

```text
hermes gateway run
```

Runtime behavior introduced:

- Read Home Assistant add-on options from `/data/options.json`.
- Create `/config/.hermes` when missing.
- Regenerate `/config/.hermes/.env` on every start so option changes are applied.
- Create `/config/.hermes/config.yaml` only on first run to protect user edits.
- Use `SUPERVISOR_TOKEN` from the add-on environment for Home Assistant auth.
- Generate first-run Hermes config with Ollama Cloud, Home Assistant, and Telegram enabled.

Narrow runtime dependencies were used instead of broad extras:

- Base editable Hermes install
- `aiohttp` for Home Assistant/API support
- `python-telegram-bot[webhooks]` for Telegram support

## Phase 3: Local Build and Startup Verification

Commit: `aa3e36b test: verify slim build and gateway startup`

Local amd64 Docker verification confirmed:

- Image builds successfully.
- Container starts and keeps `hermes gateway run` alive.
- First-run `.env` and Hermes `config.yaml` are created.
- Home Assistant/Telegram connection errors in local Docker are expected without the Supervisor network and real bot token.
- Docker inspect size was about 316 MiB, below the 500 MB target.

Fixes found during testing:

- Removed direct bashio sourcing because it failed in local HA base image execution.
- Added narrow Telegram dependency explicitly.
- Removed final-image compiler/development packages.

## Version and Configuration Cleanup

Commits:

- `0443a87 chore: set version 0.1.0 and update description`
- `c47e41e feat: add telegram_allowed_users config field`
- `5e2c232 chore: bump version to 0.1.1`

Changes:

- Set add-on versioning for the slim fork.
- Updated the add-on description.
- Added `telegram_allowed_users` so Telegram access can be limited from the Home Assistant add-on UI.
- Wrote `TELEGRAM_ALLOWED_USERS` into `/config/.hermes/.env` when configured.

## Runtime Fork Update Mechanism

Commit: `f074c5d feat: configure hermes fork update source`

The add-on repository became the Home Assistant update channel, while runtime Hermes source moved to a separate fork:

```text
https://github.com/ohnesorgen2025-svg/hermes-agent.git
```

`run.sh` now manages `/config/.hermes/hermes-agent`:

- Clone from the Hermes fork if missing.
- Set the existing clone remote to the fork.
- Fetch `main`.
- Reset only the managed source clone to `origin/main`.
- Preserve user data outside the clone: `config.yaml`, `memories/`, `sessions/`, `skills/`, and `state.db`.
- Include source revision and dependency signature in the install marker.

This lets Home Assistant offer an add-on update through `hermes_agent/config.yaml` version bumps while the add-on start refreshes the runtime Hermes source.

## Hermes-Agent Home Assistant Tools

These changes live in the separate runtime fork `ohnesorgen2025-svg/hermes-agent`.

### Automation Management

Hermes-Agent commit: `bbd51de19 feat: add home assistant automation management tool`
Add-on commit: `f2fd457 chore: bump addon version for automation tool`

Added `ha_automation_manage`:

- `list`
- `get`
- `create`
- `update`
- `delete`

Home Assistant REST endpoints:

- `GET /api/config/automation/config`
- `GET /api/config/automation/config/{automation_id}`
- `POST /api/config/automation/config/{automation_id}`
- `DELETE /api/config/automation/config/{automation_id}`
- reload via `POST /api/services/automation/reload`

Safety:

- Validates automation IDs.
- Requires `alias`, `trigger`, and `action` for create/update.
- Blocks automation actions using dangerous service domains such as `shell_command`, `command_line`, `python_script`, `pyscript`, `hassio`, and `rest_command`.

### Entity Rename

Hermes-Agent commit: `8b2880579 feat: add home assistant entity rename tool`
Add-on commit: `f8a4ce6 chore: bump addon version for entity rename tool`

Added `ha_entity_rename`:

- Validates `entity_id` with Home Assistant entity ID format.
- Requires a new friendly `name`.
- Supports optional `icon` such as `mdi:lamp`.
- Calls `POST /api/config/entity_registry/{entity_id}`.

### Zigbee2MQTT Management

Hermes-Agent commit: `44929f2be feat: add zigbee2mqtt management tool`
Add-on commit: `7e09b7a chore: bump addon version for zigbee tool`

Added `ha_zigbee_manage`, which communicates with Zigbee2MQTT through MQTT:

- `permit_join`
- `list_devices`
- `rename_device`
- `remove_device`

MQTT behavior:

- Broker host from `MQTT_HOST`, default `localhost` in Hermes runtime.
- Broker port from `MQTT_PORT`, default `1883`.
- Optional `MQTT_USER` and `MQTT_PASSWORD`.
- Uses `paho-mqtt` with optional import and a dedicated check function.
- Subscribes before publishing requests and waits for one response.
- Disconnects cleanly in error and success paths.

Safety:

- `permit_join` duration is capped at Zigbee2MQTT's 254 second limit.
- `remove_device` requires an explicit `ieee_address`.

Dependency:

- Added `paho-mqtt==2.1.0` to Hermes-Agent `[homeassistant]` optional dependency.
- Added `paho-mqtt>=2.1.0,<3` to the add-on-managed runtime dependency list.

### Matter Hub / Alexa Label Management

Hermes-Agent commits:

- `aa9bdc506 feat: add ha_matter_manage tool for Alexa entity exposure via labels`
- `b9c0e8d97 fix: use correct HA entity registry endpoints for matter manage`
- `69a0e2446 fix: use websocket API for entity registry label management`

Add-on commits:

- `8baeda2 chore: bump addon version for matter manage tool`
- `4da029e chore: bump addon version for matter manage bugfix`
- `b1123ef chore: bump addon version for websocket label fix`

Added `ha_matter_manage`, which manages the Home Assistant entity label `matter` used by Home Assistant Matter Hub for Alexa/Matter exposure:

- `expose` adds the `matter` label to an entity.
- `unexpose` removes the `matter` label from an entity.
- `list_exposed` lists entities currently labeled with `matter`.

Implementation notes:

- Initial REST attempts against `/api/config/entity_registry/...` returned `404` because the Home Assistant entity registry label write API is WebSocket-only.
- The final working implementation uses Home Assistant WebSocket commands `config/entity_registry/get` and `config/entity_registry/update` for `expose` and `unexpose`.
- `list_exposed` continues to use `POST /api/template` with `label_entities('matter')`, which works through the standard REST API.
- WebSocket authentication uses the Home Assistant token from `HASS_TOKEN` and the Supervisor proxy URL derived from `HASS_URL`.

## Bundled Device Onboarding Skill Bootstrap

The add-on now also takes responsibility for distributing a default `device-onboarding` skill to fresh Home Assistant instances without overwriting customized skills on existing instances.

Design decisions:

- The actual onboarding logic remains a Hermes skill, not hardcoded add-on logic.
- The add-on ships the skill under `hermes_agent/skill-templates/device-onboarding/` inside the image.
- On startup, `run.sh` refreshes the managed reference copy under `/config/.hermes/skill-templates/device-onboarding/`.
- If `/config/.hermes/skills/device-onboarding/` does not exist yet, `run.sh` installs that skill as the active default skill.
- If an active `device-onboarding` skill already exists, the add-on logs that it is keeping the existing skill and does not overwrite it.
- The add-on seeds `/config/.hermes/device_onboarding/known_devices.json` and its JSON schema only when those files are missing.

Bundled skill scope:

- Current bundled skill is Zigbee-focused and manually triggered.
- It uses `clarify`, `ha_zigbee_manage`, `ha_matter_manage`, and native HA area tools.
- It carries its own naming convention `funktion.raum` and Matter-offboarding safety rule.
- Home Assistant validation on 2026-05-16 confirmed native `ha_list_areas`, `ha_create_area`, and `ha_assign_area` support in the runtime.
- Future runtime work is still needed for optional Homematic capability support.

## MQTT Add-on Configuration

Commits:

- `56d9cb3 chore: add mqtt addon options`
- `ac390f6 fix: export mqtt addon environment`
- `5656200 fix: pass mqtt env directly to hermes`

The add-on gained MQTT options:

- `mqtt_host`
- `mqtt_port`
- `mqtt_user`
- `mqtt_password`

HAOS default:

```yaml
mqtt_host: core-mosquitto
mqtt_port: 1883
```

The add-on writes these values into `/config/.hermes/.env` and passes them directly to the Hermes process with `exec env`.

A secretsafe startup log line was added:

```text
[run] MQTT config: host=... port=... user_set=yes/no password_set=yes/no
```

Reason for the fix:

- Hermes initially reported `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, and `MQTT_PASSWORD` as unset.
- The tool fell back to `localhost:1883` and timed out inside the add-on container.
- `core-mosquitto` is the HAOS internal hostname for the Mosquitto add-on.
- Existing Home Assistant add-on configurations keep stored option values, so old installs may need `mqtt_host` manually changed from `localhost` to `core-mosquitto` once.

## Zigbee2MQTT End-to-End Result

Verified on Home Assistant after MQTT configuration was fixed:

- Mosquitto broker reachable at `core-mosquitto:1883`.
- Zigbee2MQTT bridge reachable through MQTT.
- `ha_zigbee_manage list_devices` returned the coordinator.
- `ha_zigbee_manage permit_join` enabled joining.
- A new ONENUO TH05Z / Tuya TS0601 temperature and humidity sensor was paired successfully.
- Device was renamed to `klima.wohnzimmer` through Zigbee2MQTT.
- Zigbee2MQTT published Home Assistant MQTT discovery topics under `homeassistant/#`.
- Home Assistant MQTT integration was added/configured.
- Home Assistant created the MQTT device `klima.wohnzimmer` with 15 entities.
- MQTT page showed two devices: `klima.wohnzimmer` and `Zigbee2MQTT Bridge`.

Important lesson:

- Mosquitto add-on and Zigbee2MQTT add-on are not enough by themselves.
- Home Assistant Core must also have the MQTT integration configured so it subscribes to discovery topics and creates entities.

## Current Capability Summary

The add-on currently provides:

- Slim Hermes gateway runtime for Home Assistant.
- Ollama Cloud model configuration.
- Telegram bot support with optional allowed-user restriction.
- Home Assistant control via Supervisor token.
- Runtime source updates from the `ohnesorgen2025-svg/hermes-agent` fork.
- Home Assistant entity listing, state lookup, service calls, automation management, entity rename, and Zigbee2MQTT management through Hermes tools.
- Home Assistant Matter Hub / Alexa exposure management through the `matter` entity label.
- MQTT configuration through Home Assistant add-on options.
- Zigbee2MQTT device pairing, listing, renaming, and removal support through Hermes.
- Bundled `device-onboarding` skill bootstrap for fresh instances, with non-destructive reference updates for existing instances.

## Operational Rules Kept

- Add-on slug remains `hermes_agent`.
- Persistent path remains `/config/.hermes`.
- `.env` is regenerated every start.
- Hermes `config.yaml` is generated only if missing.
- `SUPERVISOR_TOKEN` is read from the add-on environment and is never hardcoded.
- Hermes is not installed with `[all]`.
- User data outside `/config/.hermes/hermes-agent` is preserved during add-on updates.
