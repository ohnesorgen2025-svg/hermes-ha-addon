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

## Tools

Use these tools when available:

- `ha_dashboard_manage` for Lovelace dashboard administration
- `ha_supervisor_manage` for Supervisor, add-ons, backups, updates, and logs
- `ha_integration_manage` for config entries and repair issues
- `ha_automation_manage` for automations
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

For a test dashboard, prefer a safe URL path such as `hermes-test` and title `Hermes Test` unless the user specifies another name.

## Supervisor Workflow

When asked to administer add-ons or system updates:

1. Use read-only actions first: `info`, `list_addons`, `addon_info`, `core_info`, `supervisor_info`, `os_info`, `list_backups`, or `addon_logs`.
2. Explain what you will do.
3. Ask for confirmation before installation, update, restart, stop, uninstall, or backup operations.
4. After confirmation, execute the action and report the result.

## Integration Workflow

When asked about integrations:

1. Use `ha_integration_manage(action="list_entries")` and `ha_integration_manage(action="list_repairs")`.
2. Explain what can be done automatically.
3. Ask for confirmation before reload or removal.
4. If an integration needs OAuth, pairing, QR code, or user credentials, explain the user step clearly and continue once the user has completed it.

## Safety

Do not claim that an action succeeded unless the tool result indicates success.
If a Home Assistant internal WebSocket command is unsupported on this HA version, report the exact error and suggest the next compatible approach.
