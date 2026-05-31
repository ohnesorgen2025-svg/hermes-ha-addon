---
name: device-onboarding
description: "Router for German smart-home device onboarding: run preflight, choose Zigbee or Homematic, then hand off to the focused onboarding skill."
version: 2.4.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Smart-Home, Zigbee, Zigbee2MQTT, Homematic, Home-Assistant, Onboarding]
---

# Device Onboarding

German entry skill for adding new smart-home devices. Keep this skill short: it only checks capabilities, asks for the device technology, and then continues with the focused Zigbee or Homematic onboarding skill.

## When to Use

- User says "Gerät anlernen", "neues Gerät", "Gerät hinzufügen", "device onboarding"
- User wants to add a device but has not clearly chosen Zigbee or Homematic yet

If the user already says Zigbee, use `device-onboarding-zigbee` directly.
If the user already says Homematic, HomeMatic, HM, or HmIP, use `device-onboarding-homematic` directly.

## Core Rules

- Manual only. Do not create cron jobs or automatic detection.
- All messages to the user must be in German.
- Use `clarify` for inline keyboard selections. The `question` field contains the context; choices are short labels only.
- If prerequisites are missing, stop before pairing and explain the missing setup step.
- Do not ask for openCCU credentials during normal Homematic onboarding.

## Step 1: Capability Check

Always start generic onboarding with:

```python
ha_detect_capabilities()
```

Treat this as a hard preflight check. The add-on can guide onboarding, but Home Assistant integrations still have to exist in Home Assistant Core.

Required capabilities:

| Flow | Required before continuing | If missing |
|------|----------------------------|------------|
| Zigbee | MQTT integration in Home Assistant Core, reachable MQTT broker, Zigbee2MQTT reachable through MQTT | Stop and tell the user which part is missing. Do not start pairing. |
| Homematic | Homematic integration in Home Assistant Core with install-mode entities | Stop and tell the user to install/configure the Homematic integration first. Do not ask for CCU credentials. |

German prerequisite messages:

- Missing MQTT integration: "Die MQTT-Integration in Home Assistant ist noch nicht eingerichtet. Bitte gehe zu Einstellungen > Geräte & Dienste > Integration hinzufügen > MQTT und verbinde sie mit demselben Broker wie Zigbee2MQTT. Danach kann ich Zigbee-Geräte anlernen."
- Missing MQTT broker/Zigbee2MQTT: "Zigbee2MQTT ist noch nicht erreichbar. Bitte prüfe Mosquitto, Zigbee2MQTT und die MQTT-Zugangsdaten im Hermes Add-on. Danach starte ich den Zigbee-Anlernmodus."
- Missing Homematic integration: "Die Homematic-Integration ist in Home Assistant noch nicht eingerichtet. Bitte richte zuerst Homematic bzw. HomematicIP Local in Home Assistant ein. Danach kann ich den Anlernmodus über Home Assistant starten."

## Step 2: Choose Technology

Use `clarify` to ask which device technology should be onboarded. Only offer choices that are available according to `ha_detect_capabilities()`.

Good:

- question: "Welchen Gerätetyp möchtest du anlernen?"
- choices: ["Zigbee", "Homematic"]

If only one technology is available, ask for confirmation with that single useful path. If neither Zigbee nor Homematic is ready, do not show a technology choice; report the missing prerequisites instead.

## Step 3: Continue With Focused Skill

After the user chooses:

- Zigbee: continue with `device-onboarding-zigbee`.
- Homematic: continue with `device-onboarding-homematic`.

Do not keep the full pairing flow in this router skill. The focused skills contain the detailed rename, area, entity, and troubleshooting rules.

## Shared UX Rules

The `clarify` question field must contain the full context and question. Choices must be short, actionable labels only, normally 1-3 words.

Good:

- question: "🏠 Wohin soll das Gerät? Wähle einen Raum:"
- choices: ["wohnzimmer", "kuche", "schlafzimmer", "buero"]

Bad:

- question: "Raum?"
- choices: ["wohnzimmer als Raum wählen", "kuche als Raum wählen"]

## Data Files

- `known_devices.json` (`~/.hermes/device_onboarding/known_devices.json`) stores Zigbee IEEE addresses that have already been onboarded.
- `known_devices.schema.json` documents that file format.

These files stay with this router skill so the add-on bootstrap can seed them on first start.

## Pitfalls

- **German user** — all messages must be in German.
- **Manual-only trigger** — do not create a cron job for device detection.
- **Do not start pairing before prerequisites pass** — missing MQTT, Zigbee2MQTT, or Homematic setup must stop the flow.
- **clarify limit** — `clarify` supports max 4 choices + "Other". If more than 4 rooms exist, pick the 4 most relevant or ask a narrowing question first.
- **Use focused skills** — once the technology is known, use the dedicated skill so normal chat stays faster and less error-prone.
