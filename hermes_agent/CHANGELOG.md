# Changelog

All notable changes to this add-on are documented in this file.

The changelog is ordered from newest to oldest.

## 0.6.12 - 2026-06-10

- Upstream-Sync (2982 Commits, Base 1979ef580): Security-Hardening Approval/Memory (Promptware-Defense), Gateway-Profilsystem, Foreground-Start via HERMES_GATEWAY_NO_SUPERVISE. Security-Gates (execute_code-Policy, HA-Approval, Entity-ID-Memory-Gate) verifiziert. Details: MERGE_NOTES.md im Fork.

## 0.6.11 - 2026-06-10

- Switched the add-on back to the Hermes gateway foreground path and set the upstream `HERMES_GATEWAY_NO_SUPERVISE=1` opt-out so profile-aware runtime pins do not redirect into per-profile s6 service management inside the add-on container.

## 0.6.10 - 2026-06-10

- Reconciled profile-aware gateway service slots before startup so newer Hermes pins with the upstream profile system can still start from the add-on's existing root profile at `/config/.hermes` without manual migration.

## 0.6.9 - 2026-06-10

- Exposed the optional `hermes_ref` add-on setting so the wrapper can read a runtime ref override from `/data/options.json` without changing the default pinned revision behavior.

## 0.6.8 - 2026-06-09

- Tightened the skill-mirror secret scan to ignore placeholder/example tokens, environment-variable references, and private or localhost IP addresses.
- Kept hard blocking for real full-length tokens, private keys, literal secret assignments, and public IP addresses.

## 0.6.7 - 2026-06-09

- Added a read-only Git mirror flow for runtime skills from `/config/.hermes/skills/` via `scripts/sync-skills.sh`.
- Added a hard secret scan before any mirror commit or push; the sync aborts on likely tokens, API keys, `.env` files, SSH keys, or IP addresses.
- Added a daily cron trigger inside the add-on and documented deploy-key setup plus manual sync invocation.

## 0.6.6 - 2026-06-09

- Pinned the Hermes runtime to `cf2f6a1f2c324ca9e39bf748a88ee6faa73a4adb`.
- `ha_call_service` now routes `homeassistant.restart` and `homeassistant.stop` through the existing Home Assistant approval gate before Hermes can execute them.

## 0.6.5 - 2026-06-09

- Pinned the Hermes runtime to `2e2e08597fcf9bbcd2edef3f3c20604ec27d5e5c`.
- Home Assistant restart commands now go through the runtime approval gate instead of bypassing it via terminal-style command paths.
- Removed `execute_code` from the active default toolsets so it is no longer exposed by default in the add-on runtime.

## 0.6.2 - 2026-06-02

- Redesigned the model options UI for clarity. Two clear sections now:
  - `providers`: a repeatable list (with an "Add" button) where you pick a provider and paste its API key. Each key is stored under the correct variable automatically and appears in the Telegram `/model` picker.
  - Default/start settings: `default_provider`, `default_api_key`, `default_model`, and the advanced `model_base_url`.
- Removed the old `model_provider` / `model_api_key` / `ollama_api_key` / `ollama_model` / `model` / `extra_env` options in favour of the above. No variable names need to be known.

## 0.6.1 - 2026-06-02

- `model_provider` is now a dropdown of common providers (ollama-cloud, openrouter, deepseek, xai, anthropic, gemini, zai, nvidia, huggingface, custom, manual) instead of a free-text field.
- Added a single `model_api_key` option; the add-on maps it to the correct provider environment variable automatically, so no variable names need to be known.
- Added clear field labels and descriptions for all model options in the add-on UI (translations), replacing the stale Copilot entries.
- `extra_env` is now documented as an optional advanced escape hatch for additional providers/settings.

## 0.6.0 - 2026-06-02

- Removed the GitHub Copilot model provider (`copilot_github_token`, `copilot_model` options and `COPILOT_GITHUB_TOKEN` passthrough are gone).
- Made provider selection config-driven: `model_provider` now accepts any provider id the Hermes runtime supports (e.g. `ollama-cloud`, `openrouter`, `deepseek`, `xai`, `glm`, `kimi`, `anthropic`, `custom`), plus `manual` to keep the model section hand-editable.
- Added generic `model` and `model_base_url` options and an `extra_env` list that writes arbitrary `NAME=VALUE` pairs to `.env` so any current or future provider's API key can be set from the Home Assistant UI without code changes.
- Documented an "Adding a new model provider" workflow in DOCS.md.

## 0.5.12 - 2026-06-01

- Pinned Hermes runtime to `7f9eb23a5ec62fed4eeeb4dfb8a0861c42c7879a`, which normalizes common automation create/update payload variants such as `triggers`/`actions`/`conditions` to Home Assistant's compatible singular keys.
- Automation create/update now tolerates the common plural config form instead of depending on prompt-specific payload shaping.

## 0.5.11 - 2026-06-01

- Pinned Hermes runtime to `64f37234128cb7a6423f66185cac6f8ae995b88c`, which routes Home Assistant automation create/update writes through the supported REST config endpoint instead of the incompatible WebSocket write path on Home Assistant 2026.5.
- Normalized `enabled: false` automation create/update payloads to Home Assistant's supported `initial_state: false` config field for safer write compatibility.

## 0.5.10 - 2026-06-01

- Pinned Hermes runtime to `6768490a3c700de391ea8ae59f7283d50d41cc25`, which fixes Home Assistant 2026.5 automation config reads by using `automation/config` with `entity_id` and falls back from unsupported automation list commands to `automation.*` states plus per-entity config reads.
- Added approval gating for Home Assistant automation create/update actions in the runtime, matching delete safety behavior.
- Refined onboarding room and naming prompts so large room lists ask for a room name, German umlauts are normalized in suggested entity IDs, and typed confirmations such as `ok` accept the suggested name.
- Changed the onboarding naming convention from `funktion.raum` to `raum.funktion.option`.

## 0.5.9 - 2026-05-31

- Split the bundled `device-onboarding` skill into a small router plus focused `device-onboarding-zigbee` and `device-onboarding-homematic` skills so normal onboarding loads less context and gives more targeted guidance.
- Made the bundled `device-identification` skill feel more responsive by splitting the default listen flow into two 5-second observations with a German interim prompt when nothing is detected yet.
- Improved onboarding room selection for Home Assistant setups with more than four areas by asking the user to narrow the room list before showing filtered `clarify` choices.
- Added German user-facing failure message guidance to the bundled `home-assistant-admin` skill so technical API errors are explained in plain language.

## 0.5.8 - 2026-05-31

- Pinned Hermes runtime to `0ae2d93b80473605dce70f0f1ae70d9532f8b6d7`, which enforces approval checks for destructive Home Assistant tool actions.
- Destructive HA actions now use the same manual/smart/off approval modes as terminal commands before removing devices/integrations, deleting automations, writing config files, renaming entities, or stopping/restarting/uninstalling add-ons.

## 0.5.7 - 2026-05-31

- Added add-on managed model provider selection with `model_provider` values `ollama-cloud` and `copilot`.
- Added `copilot_github_token` and `copilot_model` options so GitHub Copilot Pro/Pro+ can be used as the Hermes model provider.
- Regenerated `.env` now includes `COPILOT_GITHUB_TOKEN` when configured and records the selected managed provider/model.

## 0.5.6 - 2026-05-30

- Fixed `HA_CONFIG_DIR` to use Home Assistant's actual add-on config mount path `/homeassistant` so `ha_config_read` and `ha_config_write` can find `configuration.yaml` and related files.

## 0.5.5 - 2026-05-30

- Mounted the Home Assistant Core config directory read-write with `homeassistant_config:rw` and exposed it to Hermes as `HA_CONFIG_DIR=/homeassistant`.
- Added runtime tools `ha_config_read`, `ha_config_write`, and `ha_config_reload` for reading YAML/config files, writing with backups and path sandboxing, and triggering `homeassistant.reload_core_config`.
- Updated admin guidance so filesystem config edits require confirmation and backups before writes.

## 0.5.4 - 2026-05-30

- Added `ha_admin_diagnose`, a read-only diagnostic tool that probes Home Assistant REST, WebSocket, Supervisor, dashboard, automation, integration, and update paths.
- Classified admin API failures such as 403 permissions, 404 missing endpoints, unsupported WebSocket commands, and connectivity problems so Hermes can choose fallback paths before claiming an action must be manual.
- Tightened the bundled admin skill so API failures trigger diagnosis and alternate adapter attempts first.

## 0.5.3 - 2026-05-30

- Fixed `ha_automation_manage` so automation list/get/create/update/delete use Home Assistant automation WebSocket config commands first, with REST fallback for older installations.
- Automation reads now return full config content such as triggers, conditions, and actions instead of failing on `/api/config/automation/config` with 404.

## 0.5.2 - 2026-05-30

- Enabled Home Assistant Supervisor API access for the add-on with `hassio_api: true` and `hassio_role: admin` so backups, Core updates, OS/Supervisor updates, and add-on updates can use the Supervisor API instead of failing with 403 from missing add-on permission.
- Added the runtime `ha_update_manage` tool for update status, `update.*` entity installs, HACS update entities, and backup-first coordinated update runs.
- Updated the bundled admin skill and docs so Hermes does not redirect update work to the UI when a technical API path exists.

## 0.5.1 - 2026-05-30

- Fixed `ha_dashboard_manage` so dashboard metadata updates such as `show_in_sidebar`, `icon`, `title`, and `require_admin` use the Home Assistant Lovelace dashboard REST API.
- Kept dashboard config saves on the Lovelace WebSocket API and followed metadata updates via REST when `save_dashboard` includes metadata fields.
- Changed dashboard deletion to use `DELETE /api/lovelace/dashboards/{dashboard_id}` and kept dashboard backups before writes.

## 0.5.0 - 2026-05-29

- Added Home Assistant admin runtime tools: `ha_dashboard_manage`, `ha_supervisor_manage`, and `ha_integration_manage`.
- Added the bundled `home-assistant-admin` skill for dashboard, add-on, update, backup, integration, and system administration workflows.
- Pinned the runtime fork to a revision that exposes Lovelace dashboard management, Supervisor API management, and integration/repair inspection.
- Documented the authority model: read-only inspection is allowed directly; write, destructive, disruptive, and broad admin actions require chat confirmation, then execute without extra hurdles.

## 0.4.1 - 2026-05-29

- Improved `ha_observe_changes` scoring for dimmers, remotes, wall switches, and scene controllers that trigger many lights or switches at once.
- Marked multi-actuator bursts as cascades and ranked likely controller/action entities above downstream lamp changes.
- Updated the bundled `device-identification` skill guidance for Dimmer-Kaskaden.

## 0.4.0 - 2026-05-29

- Added the bundled `device-identification` skill. In Telegram, phrases like "Lauschen" or "Welches Gerät ist das?" start a short Home Assistant event observation flow.
- Pinned the runtime fork to a revision that adds `ha_observe_changes`, a WebSocket-based Home Assistant `state_changed` listener for identifying recently triggered devices.
- Changed bundled skill startup sync so every bundled skill template is installed into the active Hermes skills directory, not only `device-onboarding`.
- Kept the observer window short by default: 10 seconds, with a hard maximum of 20 seconds to reduce background telemetry noise.

## 0.3.9 - 2026-05-29

- Applied `ollama_model` add-on option changes to existing Hermes configs when the config still uses the managed `ollama-cloud` model block.
- Wrote `OLLAMA_MODEL` into `/config/.hermes/.env` and passed it to the Hermes process for easier runtime inspection.
- Documented that `ollama_model` is synced on startup for managed Ollama Cloud configs, while non-Ollama custom model configs are left unchanged.

## 0.3.8 - 2026-05-21

- Pinned the default Hermes runtime fork revision instead of following `main` on every add-on start.
- Kept `auto_update: true` as an explicit opt-in path for tracking the runtime fork's `main` branch.
- Improved runtime checkout handling so branches, tags, and commit hashes can be used through `HERMES_REF`.
- Restored Telegram allowed-user and MQTT add-on options in the Home Assistant config schema and runtime environment.
- Documented onboarding preflight checks for MQTT/Zigbee2MQTT and Homematic integrations.
- Clarified that diverging active `device-onboarding` skills are backed up before the bundled copy is synced.
- Updated the bundled `device-onboarding` skill to stop before pairing when required Home Assistant integrations are missing.

## 0.3.7 - 2026-05-18

- Added immediate confirmation feedback after starting Zigbee or Homematic pairing/install mode.
- The onboarding flow no longer leaves the user in silence after activating an anlernmodus.

## 0.3.6 - 2026-05-18

- Reworked the bundled `device-onboarding` Homematic flow to use Home Assistant discovery instead of asking for openCCU web UI credentials.
- The skill now searches Homematic integration entities dynamically for install-mode buttons and duration/status sensors.
- Added a clear HA-based start path for Homematic devices: discover, press install mode, wait, detect, rename, and assign area.

## 0.3.5 - 2026-05-18

- Changed startup behavior to always sync the active `device-onboarding` skill from the bundled template.
- Added automatic backups for diverging active skill versions before overwrite (`/config/.hermes/skill-backups`).
- Removes the need for manual terminal cleanup when onboarding skill updates are released.

## 0.3.4 - 2026-05-18

- Extended bundled `device-onboarding` to a unified "Gerät anlernen" entry with Zigbee or Homematic selection.
- Added capability-based onboarding branching to check whether Homematic is configured in Home Assistant before continuing.
- Added runtime support for `ha_detect_capabilities` (MQTT, Matter, Homematic integration detection).
- Simplified add-on options and runtime environment writing to the minimal gateway-focused set.
- Removed the remaining non-essential package (`sqlite3`) from the add-on image.

## 0.3.3 - 2026-05-17

- Published the add-on changelog for Home Assistant update dialogs.
- No runtime behavior changes.

## 0.3.2 - 2026-05-16

- Added safe auto-sync for the bundled `device-onboarding` skill.
- Existing active skills are now updated automatically when they still match the previous add-on-managed version.
- Locally customized active skills are preserved.
- Added migration logic for older managed skills created before sync markers existed.

## 0.3.1 - 2026-05-16

- Bundled the default `device-onboarding` skill into the add-on image.
- Installed the default onboarding skill automatically on fresh instances.
- Seeded `known_devices.json` and its schema for the onboarding flow.
- Added documentation for bundled skill bootstrap behavior.

## 0.3.0 - 2026-05-14

- Updated Matter/Alexa label management to use the correct Home Assistant WebSocket entity-registry API.
- Released the working fix for `ha_matter_manage` label updates.

## 0.2.9 - 2026-05-14

- Added a bugfix release for `ha_matter_manage` after the first implementation.
- Improved Matter/Alexa entity exposure handling.

## 0.2.8 - 2026-05-14

- Added native `ha_matter_manage` support in the runtime fork.
- Added Alexa/Home Assistant Matter Hub exposure management through the `matter` label.

## 0.2.7 - 2026-05-14

- Expanded add-on documentation for Zigbee2MQTT setup and overall add-on evolution.
- Documented the validated Zigbee pairing flow and MQTT integration requirements.

## 0.2.6 - 2026-05-14

- Fixed direct propagation of MQTT environment variables into the Hermes process.
- Ensured Zigbee2MQTT tooling receives the configured broker settings at runtime.

## 0.2.5 - 2026-05-13

- Fixed MQTT add-on environment export.
- Switched the default MQTT host to `core-mosquitto` for HAOS setups.

## 0.2.4 - 2026-05-13

- Added MQTT add-on options: `mqtt_host`, `mqtt_port`, `mqtt_user`, and `mqtt_password`.
- Extended the config schema for Zigbee2MQTT support.

## 0.2.3 - 2026-05-13

- Added native Zigbee2MQTT device management through `ha_zigbee_manage`.
- Added pairing, device listing, renaming, and removal support through MQTT.

## 0.2.2 - 2026-05-13

- Added native Home Assistant entity rename support in the runtime fork.
- Exposed entity rename functionality through the add-on release.

## 0.2.1 - 2026-05-13

- Added native Home Assistant automation management support.
- Exposed automation list, get, create, update, and delete operations through Hermes.

## 0.2.0 - 2026-05-13

- Configured the add-on to refresh Hermes from the maintained `ohnesorgen2025-svg/hermes-agent` fork.
- Preserved user data while resetting only the managed runtime source clone on startup.

## 0.1.1 - 2026-05-11

- Added `telegram_allowed_users` to the add-on configuration.
- Improved Telegram access restriction for the gateway bot.

## 0.1.0 - 2026-05-11

- First slim fork release for Raspberry Pi oriented gateway mode.
- Removed browser tooling, terminal UI, nginx ingress, and other add-on bloat.
- Switched the add-on to Ollama Cloud plus Telegram focused operation.

## Pre-fork History

These versions belong to the earlier upstream-style add-on history before this slim fork reset to `0.1.0`.

### 1.0.4 - 2026-04-24

- Final pre-fork upstream-style release before the slim reset.

### 1.0.3 - 2026-04-20

- Third stable upstream-style release.

### 1.0.2 - 2026-04-20

- Second stable upstream-style release.

### 1.0.1 - 2026-04-17

- Follow-up upstream-style release after web dashboard integration work.

### 1.0.0 - 2026-03-27

- First stable upstream-style release.