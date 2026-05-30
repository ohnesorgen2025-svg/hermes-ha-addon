---
name: home-assistant-admin
description: "Administer Home Assistant dashboards, add-ons, updates, backups, integrations, entities, automations, and system state with chat confirmation for risky actions."
version: 1.0.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Home-Assistant, Admin, Dashboards, Add-ons, Integrations, Supervisor]
---

# Home Assistant Admin

Use this skill when the user asks you to administer Home Assistant, including dashboards, integrations, add-ons, updates, backups, entities, areas, automations, Matter/Alexa exposure, Zigbee2MQTT, or system status.

## Authority Model

The user wants a capable Home Assistant admin assistant. You may use the available Home Assistant admin tools to perform administration after chat confirmation.

Read-only actions do not require confirmation:

- list dashboards, views, cards, entities, areas, devices, services, integrations, repairs, add-ons, backups, logs, versions, and update status
- inspect an existing dashboard or config entry
- summarize possible changes

Ask for explicit chat confirmation before write, destructive, disruptive, or broad actions:

- create, save, rename, or delete dashboards/views/cards
- install, uninstall, start, stop, restart, or update add-ons
- update Home Assistant Core, Supervisor, or OS
- remove or reload integrations/config entries
- create or restore backups
- rename entities, assign areas, change labels, expose/unexpose Matter entities
- run raw Supervisor or WebSocket commands

After the user confirms, execute without adding extra artificial hurdles.

## Failure Handling

Do not claim that Home Assistant requires manual UI work just because one API call failed.

When an admin action fails with 403, 404, unsupported WebSocket command, service not found, or another adapter-path error:

1. Run `ha_admin_diagnose(action="quick")` for a fast read-only capability check.
2. Use the diagnosis to choose an alternate path: WebSocket, REST, Supervisor API, service/entity call, or update entity.
3. If the alternate path is available, continue after any required user confirmation.
4. Only tell the user manual UI work is required when diagnosis shows no available API/service path or the workflow truly requires OAuth, pairing, QR code, credentials, or another human-only step.
5. Report the exact blocked path and classification, for example permission, missing endpoint, unsupported WebSocket command, or connectivity.

## Tools

Use these tools when available:

- `ha_dashboard_manage` for Lovelace dashboard administration
- `ha_supervisor_manage` for Supervisor, add-ons, backups, updates, and logs
- `ha_update_manage` for update status, Home Assistant `update.*` entities, HACS update entities, and backup-first coordinated update runs
- `ha_admin_diagnose` for read-only API capability checks and failure classification
- `ha_config_read`, `ha_config_write`, and `ha_config_reload` for Home Assistant Core config files below `/config`
- `ha_integration_manage` for config entries and repair issues
- `ha_automation_manage` for full automation configs, including triggers, conditions, and actions
- `ha_entity_rename`, `ha_list_areas`, `ha_create_area`, `ha_assign_area` for entities and rooms
- `ha_matter_manage` for Matter/Alexa exposure through the `matter` label
- `ha_zigbee_manage` for Zigbee2MQTT device management
- `ha_list_entities`, `ha_get_state`, `ha_list_services`, and `ha_call_service` for normal HA inspection and service calls

## Dashboard Workflow

When asked to create or change dashboards:

1. Use `ha_dashboard_manage(action="list_dashboards")` when you need to identify the target dashboard.
2. Use `ha_dashboard_manage(action="get_dashboard", url_path="...")` to inspect it.
3. Propose a concise plan.
4. Ask for confirmation.
5. After confirmation, use `create_dashboard`, `add_view`, `add_card`, `save_dashboard`, or related actions.
6. Report what changed and mention the backup path if one was created.

Dashboard config is stored separately from dashboard metadata in Home Assistant. Use dashboard metadata fields (`title`, `icon`, `show_in_sidebar`, `require_admin`) on `update_dashboard` or `save_dashboard` when changing sidebar visibility, icons, titles, or admin-only access.

For a test dashboard, prefer a safe URL path such as `hermes-test` and title `Hermes Test` unless the user specifies another name.

## Config File Workflow

When asked to inspect or change YAML/config files such as `configuration.yaml`, `scripts.yaml`, `scenes.yaml`, templates, packages, or custom includes:

1. Use `ha_config_read(path="...")` to inspect the current file content.
2. Explain the intended edit and ask for confirmation before writing.
3. Use `ha_config_write(path="...", content="...")` with the full new file content. It creates a backup before writing and keeps paths sandboxed below `/config`.
4. Use `ha_config_reload()` when the change requires `homeassistant.reload_core_config`.
5. Report the written path, backup path, and reload result.

## Supervisor Workflow

When asked to administer add-ons or system updates:

1. Use read-only actions first: `ha_update_manage(action="status")`, `ha_update_manage(action="list_updates")`, `info`, `list_addons`, `addon_info`, `core_info`, `supervisor_info`, `os_info`, `list_backups`, or `addon_logs`.
2. Explain what you will do, including whether a backup will be created first.
3. Ask for confirmation before installation, update, restart, stop, uninstall, or backup operations.
4. After confirmation, use `ha_update_manage` for update runs. Use Supervisor actions directly when the user targets one specific add-on or Supervisor component.
5. Report the result, including backup status and any update entity or add-on that failed.

Do not tell the user to perform updates manually while a Home Assistant API, Supervisor API, or update entity path exists. HACS integrations and frontend resources are usually updated through Home Assistant `update.*` entities with `ha_update_manage`, not through Supervisor add-on updates.

## Automation Workflow

When asked which automation uses an entity, device, button, dimmer, or scene controller:

1. Use `ha_automation_manage(action="list")` to inspect automation configs.
2. Use `ha_automation_manage(action="get", automation_id="...")` when you need the full trigger, condition, or action body for one automation.
3. Search triggers, conditions, and actions before concluding that an automation is unrelated.
4. Ask for confirmation before changing or deleting automations.

## Integration Workflow

When asked about integrations:

1. Use `ha_integration_manage(action="list_entries")` and `ha_integration_manage(action="list_repairs")`.
2. Explain what can be done automatically.
3. Ask for confirmation before reload or removal.
4. If an integration needs OAuth, pairing, QR code, or user credentials, explain the user step clearly and continue once the user has completed it.

## Safety

Do not claim that an action succeeded unless the tool result indicates success.
If a Home Assistant internal WebSocket command is unsupported on this HA version, report the exact error and suggest the next compatible approach.
