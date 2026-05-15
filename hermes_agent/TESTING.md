# Test Report

## Phase 3: Slim Build and Gateway Startup

Date: 2026-05-11
Host: macOS with Docker Desktop 29.2.1
Target platform: linux/amd64
Image tag: `hermes-ha-addon-slim:latest`

## Build

Command:

```bash
docker build --no-cache --platform linux/amd64 \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm \
  -t hermes-ha-addon-slim .
```

Result: success.

## Container Startup

Command:

```bash
docker run -d --platform linux/amd64 \
  --name hermes-ha-addon-slim-test \
  -e SUPERVISOR_TOKEN=test \
  -v "$PWD/test-config:/config" \
  -v "$PWD/test-data:/data:ro" \
  hermes-ha-addon-slim
```

Observed startup sequence:

```text
[run] Writing /config/.hermes/.env
[run] Creating first-run Hermes config
[run] Cloning Hermes Agent...
[run] Creating Python environment...
[run] Installing Hermes Agent...
 + hermes-agent==0.13.0 (from file:///config/.hermes/hermes-agent)
 + python-telegram-bot==22.7
[run] Starting Hermes Gateway
```

Container state after startup:

```text
running 0
```

Local Docker caveat: the gateway logs expected platform connection errors because this test container is not running inside the Home Assistant Supervisor network and the test config does not include a real Telegram bot token:

```text
[Homeassistant] Failed to connect: Cannot connect to host supervisor:80
[Telegram] No bot token configured
```

These errors did not terminate the gateway process. They are external test-environment limitations, not image or entrypoint startup failures.

## Image Size

Measured with Docker inspect:

```text
331697017 bytes
```

That is about 316 MiB and is below the 500 MB target.

Docker Desktop also reported this virtual/uncompressed display size:

```text
REPOSITORY             TAG       SIZE
hermes-ha-addon-slim   latest    1.32GB
```

Layer analysis showed the largest remaining layers are runtime dependencies required by the current design: Debian runtime packages, Node.js 22, and uv.

## Fixes Found During Test

- Removed direct bashio sourcing from `run.sh`; local HA base image execution failed with `/usr/lib/bashio/bashio: line 25: 1: script to source must be provided`.
- Added the narrow Telegram runtime dependency `python-telegram-bot[webhooks]>=22.6,<23` instead of using Hermes `[all]` or broad `[messaging]` extras.
- Removed final-image compiler and development packages from the Dockerfile.

## Update Mechanism Test

Date: 2026-05-13
Image tag: `hermes-ha-addon-slim:latest`

Verified behavior:

- Created the fork `ohnesorgen2025-svg/hermes-agent` from `NousResearch/hermes-agent`.
- Built the add-on image with the new `run.sh`.
- Started with an existing `/config/.hermes` test directory containing preserved `config.yaml`, `memories/`, `sessions/`, `skills/`, and `state.db` marker files.
- Confirmed the managed source clone uses `https://github.com/ohnesorgen2025-svg/hermes-agent.git` as `origin`.
- Confirmed an existing clone is refreshed with `git fetch` and `git reset --hard origin/main`.
- Confirmed `.env` is regenerated and includes `TELEGRAM_ALLOWED_USERS` when configured.
- Confirmed existing user data outside `/config/.hermes/hermes-agent` is preserved.
- Confirmed the install marker now includes both the source revision and add-on-managed dependency signature.

Observed update-path startup sequence:

```text
[run] Writing /config/.hermes/.env
[run] Updating Hermes Agent source from https://github.com/ohnesorgen2025-svg/hermes-agent.git (main)...
HEAD is now at 1979ef580 chore(release): map iuyup author for PR #6155 salvage
[run] Installing Hermes Agent...
 + aiohttp==3.13.5
 ~ hermes-agent==0.13.0 (from file:///config/.hermes/hermes-agent)
[run] Starting Hermes Gateway
```

Container state after update-path startup:

```text
running 0
```

Local Docker caveat: Home Assistant and Telegram connection warnings are expected without the Supervisor network and a real Telegram bot token. The gateway process remained running.

## Zigbee2MQTT End-to-End Test

Date: 2026-05-14
Environment: Home Assistant OS with Mosquitto add-on, Zigbee2MQTT add-on, and Home Assistant MQTT integration

Verified behavior:

- Hermes add-on reads MQTT settings from Home Assistant add-on options.
- Add-on startup log reports MQTT configuration without exposing secrets:

```text
[run] MQTT config: host=core-mosquitto port=1883 user_set=yes password_set=yes
```

- `ha_zigbee_manage list_devices` connected to Zigbee2MQTT through Mosquitto and returned the coordinator.
- `ha_zigbee_manage permit_join` enabled pairing.
- A new ONENUO TH05Z / Tuya TS0601 temperature and humidity sensor paired successfully.
- Device interview completed successfully.
- Device was renamed to `klima.wohnzimmer`.
- Zigbee2MQTT published retained Home Assistant discovery topics under `homeassistant/#`.
- After the Home Assistant MQTT integration was configured, Home Assistant created:
  - MQTT device `klima.wohnzimmer`
  - Zigbee2MQTT Bridge device
  - 15 entities for the sensor

Important finding:

- Mosquitto broker add-on and Zigbee2MQTT add-on are not enough for Home Assistant entities.
- Home Assistant Core must also have the MQTT integration configured and connected to the same broker.

## Matter Hub / Alexa Label Management Test

Date: 2026-05-14
Environment: Home Assistant OS with Home Assistant Matter Hub

Verified behavior:

- `ha_matter_manage list_exposed` uses the Home Assistant template endpoint with `label_entities('matter')` and returns the current labeled entities.
- `ha_matter_manage expose` updates a Home Assistant entity registry entry by adding the `matter` label.
- `ha_matter_manage unexpose` updates the same registry entry by removing the `matter` label.
- Home Assistant Matter Hub observes the `matter` label and updates the set of entities exposed to Alexa/Matter.

Important finding:

- Home Assistant entity registry label writes are WebSocket-only.
- REST calls to `/api/config/entity_registry/...` return `404` for this workflow.
- The working implementation uses WebSocket commands `config/entity_registry/get` and `config/entity_registry/update` with the add-on `HASS_TOKEN`.

## Bundled Device Onboarding Bootstrap Validation

Date: 2026-05-16
Environment: macOS with Docker Desktop, local `linux/amd64` smoke test using a temporary `/config`

Verified behavior:

- The add-on image includes `skill-templates/device-onboarding/` and copies it into the container at `/addon-skill-templates/`.
- First startup wrote `/config/.hermes/.env`, created the first-run Hermes config, installed bundled skill templates, installed the default active `device-onboarding` skill, and seeded `/config/.hermes/device_onboarding/known_devices.json` and `known_devices.schema.json`.
- The temporary test config contains both `/config/.hermes/skill-templates/device-onboarding/` and `/config/.hermes/skills/device-onboarding/` after first startup.
- Second startup with a locally modified active skill logged `Keeping existing device-onboarding skill`, and the local marker in `SKILL.md` remained intact.
- The bundled `known_devices.json` starts empty, so new installations do not inherit existing Zigbee device identities.

Observed limitations in the local smoke test:

- Gateway startup then failed to connect to Home Assistant and Telegram because the container was not running inside the Home Assistant Supervisor network and no real Telegram bot token was configured.
- Docker reported `hermes-ha-addon-slim-test:latest 1.32GB` for the local image, so the original sub-500-MB target still needs separate follow-up work if that target remains mandatory.

## Native HA Area Tools Validation

Date: 2026-05-16
Environment: Home Assistant OS with updated Hermes add-on and runtime commit `ae06dce58`

Verified behavior:

- `ha_list_areas` returned the existing Home Assistant areas with `area_id` and display name.
- `ha_create_area` created a temporary test area `Testzimmer` with normalized `area_id` `testzimmer`.
- `ha_assign_area` assigned `sensor.0xa4c138f531a61971_temperature` to `testzimmer` successfully.
- Cleanup was completed after the test: the entity assignment was removed again and the temporary area was deleted.

Current gap:

- Area deletion is still not a native Hermes tool path. Cleanup used the existing WebSocket-based fallback.

## Native HA Entity Rename Follow-Up

Date: 2026-05-16
Environment: runtime implementation updated in `hermes-agent`, live HA validation still pending

Implemented behavior:

- `ha_entity_rename` now uses Home Assistant WebSocket command `config/entity_registry/update` instead of the non-working REST path.
- The tool now supports `name`, `icon`, `new_entity_id`, and `area_id` in one call.
- This is intended to fix MQTT/Zigbee onboarding where HA keeps IEEE-based entity IDs after Zigbee2MQTT rename.

Pending validation:

- Live Home Assistant test is still needed for renaming a real MQTT entity from an IEEE-based ID to a readable final `entity_id`.
