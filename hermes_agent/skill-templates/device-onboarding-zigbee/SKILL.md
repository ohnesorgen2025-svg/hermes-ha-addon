---
name: device-onboarding-zigbee
description: "German Zigbee device onboarding through Zigbee2MQTT: permit join, detect new devices, name, assign area, rename HA entities, and update known_devices."
version: 1.0.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Smart-Home, Zigbee, Zigbee2MQTT, Home-Assistant, Onboarding]
---

# Zigbee Device Onboarding

Use this skill when the user wants to add, pair, rename, place, or remove a Zigbee device.

## Core Rules

- All messages to the user must be in German.
- Manual only. The user initiates pairing.
- Do not call `permit_join` until the Zigbee preflight passes.
- Do not guess Home Assistant entity IDs. Always verify with `ha_list_entities()`.
- Use `clarify` for room, name, and confirmation choices. Keep choices short.

## Preflight

Before starting pairing, confirm all checks are green:

1. Home Assistant Core has the MQTT integration configured.
2. The MQTT broker is reachable from Hermes.
3. Zigbee2MQTT responds to:

```python
ha_zigbee_manage(action="list_devices")
```

If any check fails, stop and explain the missing prerequisite in German. Do not call `permit_join`.

Useful German messages:

- Missing MQTT integration: "Die MQTT-Integration in Home Assistant ist noch nicht eingerichtet. Bitte gehe zu Einstellungen > Geräte & Dienste > Integration hinzufügen > MQTT und verbinde sie mit demselben Broker wie Zigbee2MQTT. Danach kann ich Zigbee-Geräte anlernen."
- Missing MQTT broker/Zigbee2MQTT: "Zigbee2MQTT ist noch nicht erreichbar. Bitte prüfe Mosquitto, Zigbee2MQTT und die MQTT-Zugangsdaten im Hermes Add-on. Danach starte ich den Zigbee-Anlernmodus."

## Pairing Flow

### Step 1: Snapshot Existing Devices

List devices before pairing:

```python
ha_zigbee_manage(action="list_devices")
```

Compare this with `~/.hermes/device_onboarding/known_devices.json`. Known devices are IEEE addresses already onboarded. Always ignore devices with `type: "Coordinator"`.

### Step 2: Enable Pairing

```python
ha_zigbee_manage(action="permit_join", duration=120)
```

Immediately tell the user:

> ✅ Zigbee-Anlernmodus ist jetzt aktiv. Bitte versetze das Gerät jetzt in den Pairing-Modus.

Tell the user to hold the reset/pair button for about 5-10 seconds if needed.

### Step 3: Detect New Device

Wait at least 20-30 seconds, then call:

```python
ha_zigbee_manage(action="list_devices")
```

New devices are devices whose `ieee_address` is not in `known_devices.json` and whose `type` is not `Coordinator`.

If no new device appears yet, wait another 30 seconds and check again. Pairing can take up to 60 seconds.

If a device shows `interview_state: "FAILED"` or `type: "Unknown"`, explain that Zigbee2MQTT could not identify it yet. Ask the user to reset the device and try pairing again. After repeated failures, say the device may be unsupported by Zigbee2MQTT.

When a new device is found, answer compactly:

> ✅ Neues Gerät erkannt: [description]\nHersteller: [vendor] | Modell: [model]\nIEEE: [ieee_address] | Name: [friendly_name] | Strom: [power_source]

## Room Assignment

List areas with:

```python
ha_list_areas()
```

Use `clarify`:

- question: "🏠 Wohin soll das Gerät? Wähle einen Raum:"
- choices: short room labels such as ["wohnzimmer", "kuche", "schlafzimmer", "buero"]

If Home Assistant has more than 4 areas, do not guess four rooms silently. First show a compact German room overview grouped alphabetically or by likely relevance, then ask the user to type a room name or a few letters to filter the list. After the user narrows it down, use `clarify` with at most 4 matching rooms plus the normal typed-name fallback.

Example:

> Ich habe mehr als vier Räume gefunden: Arbeitszimmer, Bad, Büro, Flur, Küche, Schlafzimmer, Wohnzimmer. Für welchen Raum ist das Gerät? Du kannst den Namen oder ein paar Buchstaben schreiben.

If the user types a new room name, create it:

```python
ha_create_area(name="Büro")
```

Use the returned `area_id`, not the display name, for later assignments. Home Assistant may normalize umlauts, e.g. `Büro` to `buero`.

## Name Assignment

Suggest a name following `funktion.raum`. Inspect existing entities in the room first so you do not propose a duplicate name.

```python
ha_list_entities(area="buero")
```

If `licht.buero` already exists, prefer a more specific or numbered suggestion such as `licht.buero_decke`, `licht.buero_schreibtisch`, or `licht.buero_2`.

Naming hints:

| Z2M Description Keywords | Function Prefix | German Type Name |
|--------------------------|-----------------|------------------|
| temperature, humidity, climate, thermostat | klima | Temperatur-/Feuchtigkeitssensor |
| light, bulb, lamp, dimmer, LED | licht | Licht |
| plug, outlet, socket, steckdose | steckdose | Steckdose |
| motion, occupancy, presence, luminance | bewegung | Bewegungsmelder |
| door, window, contact, open/close | tuer/fenster | Tür-/Fenster-Sensor |
| switch, button, remote | schalter | Schalter |
| water leak, moisture | wasser | Wassersensor |
| smoke | rauch | Rauchmelder |
| vibration | vibration | Vibrationsmelder |
| blind, curtain, shade | rollladen | Rollladen |
| lock | schloss | Schloss |
| power, energy, meter | stromzahler | Stromzähler |

Use `clarify` with the suggested name and "Anderer Name".

Good:

- question: "📝 Gerät benennen. Vorschlag nach Konvention funktion.raum:"
- choices: ["licht.buero ✅", "Anderer Name"]

## Confirmation

Put the summary in the `question` field and keep choices short:

- question: "Alles richtig?\n📋 Zusammenfassung:\n• Name: schreibtischlampe.buero\n• Raum: Büro\n• Typ: IKEA TRADFRI LED1836G9"
- choices: ["✅ Bestätigen", "✏️ Ändern"]

## Apply Changes

After confirmation:

1. Rename in Zigbee2MQTT:

```python
ha_zigbee_manage(action="rename_device", friendly_name="[ieee_or_old_name]", new_name="[chosen_name]")
```

2. Wait 10-15 seconds for MQTT autodiscovery to refresh Home Assistant entities.
3. Find all actual Home Assistant entities for the new device with `ha_list_entities()`. New MQTT entities may still use IEEE-based IDs.
4. Rename and place every entity with one call each:

```python
ha_entity_rename(
  entity_id="sensor.0xa4c138f531a61971_temperature",
  new_entity_id="sensor.klima_buero_temperature",
  name="Klima Büro Temperatur",
  area_id="buero",
)
```

5. Verify with `ha_list_entities(area="chosen_area")`.
6. Append the IEEE address to `~/.hermes/device_onboarding/known_devices.json`.
7. Tell the user what was created and whether any manual step remains.

## Device Offboarding

Use this flow when the user wants to remove, delete, or "ablernen" a Zigbee device.

### Step 1: Confirm Device

Use `clarify` to confirm the exact device. Show device name, model, and IEEE address.

### Step 2: Remove Matter/Alexa Exposure First

Before removing from Zigbee2MQTT, check Matter exposure:

```python
ha_matter_manage(action="list_exposed")
```

If any entity from the device is exposed, unexpose each one first:

```python
ha_matter_manage(action="unexpose", entity_id="light.schreibtischlampe_buero")
```

Only proceed once all related `matter` labels are removed. Otherwise Alexa/Matter exposure can persist or reappear when the device is paired again.

### Step 3: Remove From Zigbee2MQTT

```python
ha_zigbee_manage(action="remove_device", friendly_name="<ieee_address_or_friendly_name>")
```

This sends a network leave command and removes the device from Zigbee2MQTT.

### Step 4: Update known_devices

Remove the device IEEE address from `~/.hermes/device_onboarding/known_devices.json`.

### Step 5: Remind User

Tell the user to factory-reset the physical device if they want to pair it elsewhere.

## Pitfalls

- **MQTT config entry required** — if MQTT entities exist but entity registry operations return 404, the Home Assistant MQTT integration is missing or not a config entry.
- **Rename every MQTT entity explicitly** — Zigbee2MQTT rename does not guarantee readable Home Assistant `entity_id` values.
- **Entity discovery delay** — after Zigbee2MQTT rename, wait 10-15 seconds before assigning entities.
- **Multiple entities per device** — search by IEEE address and assign all related entities, including hidden/common entities such as linkquality, identify buttons, update entities, selects, and numbers.
- **Do not rename the coordinator** — always filter out devices with `type: "Coordinator"`.
- **MQTT_HOST** — on HAOS, this is usually `core-mosquitto`, not `localhost`.
- **Automation entity verification** — verify actual entity IDs before creating automations. Do not construct IDs from friendly names.
