# Changelog

All notable changes to this add-on are documented in this file.

The changelog is ordered from newest to oldest.

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