---
name: device-onboarding
description: "Unified device onboarding: choose Zigbee or Homematic, then guide setup and HA integration with inline keyboards (clarify)."
version: 2.0.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Smart-Home, Zigbee, Zigbee2MQTT, Homematic, Home-Assistant, Onboarding]
---

# Device Onboarding

Interactive onboarding flow for new smart-home devices (Zigbee and Homematic) — manually triggered when the user says they want to add a device.

## When to Use

- User says "Gerät anlernen", "neues Gerät", "Gerät hinzufügen", "device onboarding"
- User explicitly asks to pair a Zigbee or Homematic device

## Architecture

**Trigger:** Manual only. No cron job, no automatic detection. The user initiates by saying they want to pair a device.

**Flow:** Agent-driven, using `clarify` for inline keyboard selections (room, name, confirmation).

## Onboarding Flow

### Step 0: Detect Capabilities + Choose Technology

Always start with a capability check:

```python
ha_detect_capabilities()
```

Then use `clarify` to ask which device technology should be onboarded.

If the user chooses **Zigbee**, follow the Zigbee flow below.

If the user chooses **Homematic**:

- If `homematic_configured` is `false`, run a guided setup for Home Assistant integration first:
  1. Explain that CCU/Funkmodul can exist physically, but Home Assistant still needs a configured Homematic integration.
  2. Guide to: Einstellungen -> Geräte & Dienste -> Integration hinzufügen -> Homematic(IP) Local.
  3. Ask for confirmation once the integration is configured.
  4. Re-run `ha_detect_capabilities()` and continue only when `homematic_configured=true`.
- If `homematic_configured` is `true`, continue with Homematic onboarding guidance:
  1. Ask the user to put the Homematic device into teach-in mode.
  2. Guide through adding the device inside the Homematic integration flow in Home Assistant.
  3. After detection, continue with room assignment (use native area tools) and entity naming conventions (same naming rules as Zigbee).

## Zigbee Flow

When the user says "Gerät anlernen" or similar:

### Step 1: Enable Pairing Mode

```python
ha_zigbee_manage(action="permit_join", duration=120)
```

Tell the user to put the physical device in pairing mode (hold reset/pair button 5-10s).

Wait at least 20-30 seconds, then check for new devices:

```python
ha_zigbee_manage(action="list_devices")
```

Compare the device list against known devices in `~/.hermes/device_onboarding/known_devices.json`. New devices = those whose `ieee_address` is NOT in the file AND whose `type` is NOT "Coordinator".

If no new device appears yet, wait another 30s and check again. The pairing can take up to 60s.

### Step 2: Detection Notification

```
✅ Neues Gerät erkannt: [description]
   Hersteller: [vendor] | Modell: [model]
   IEEE: [ieee_address] | Name: [friendly_name] | Strom: [power_source]
```

### Step 3: Room Assignment (Inline Keyboard)

Fetch current HA areas via Supervisor API:
```bash
curl -s -X POST "http://supervisor/core/api/template" \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"template":"{{ areas() }}"}'
```

**IMPORTANT clarify UX rule:** The `question` field must contain the full context and question. The `choices` must be short, actionable labels only (1-3 words). Never put explanatory text in the choices — put it in the question. The user reads the question first, then sees the buttons below it.

Good:
- question: "🏠 Wohin soll das Gerät? Wähle einen Raum:"
- choices: ["wohnzimmer", "kuche", "schlafzimmer", "buero"]

Bad:
- question: "Raum?"
- choices: ["wohnzimmer als Raum wählen", "kuche als Raum wählen", ...]

If the user types a new room name (e.g., "Büro"), note it — a new area will need to be created in HA later.

### Step 4: Name Assignment

Based on the selected room and device type (from Step 1), suggest a name following the convention `funktion.raum`:

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

Use `clarify` with the suggested name and "Anderer Name" as choices. Context goes in the question, short labels in choices:

Good:
- question: "📝 Gerät benennen. Vorschlag nach Konvention funktion.raum:"
- choices: ["licht.buero ✅", "Anderer Name"]

Bad:
- question: "Name?"
- choices: ["licht.buero als Namen bestätigen", "Anderen Namen eingeben"]

### Step 5: Summary + Confirmation

Put the full summary in the `question` field, keep choices short:

Good:
- question: "Alles richtig?\n📋 Zusammenfassung:\n• Name: schreibtischlampe.buero\n• Raum: Büro\n• Typ: IKEA TRADFRI LED1836G9"
- choices: ["✅ Bestätigen", "✏️ Ändern"]

Bad:
- question: "Bestätigen?"
- choices: ["Ja, bestätigen und erstellen", "Nein, ich möchte Änderungen vornehmen"]

### Step 6: Apply Changes

On confirmation:

1. **Rename in Z2M**: `ha_zigbee_manage(action="rename_device", friendly_name="[ieee_or_old_name]", new_name="[chosen_name]")`
2. **Wait 10-15s** for MQTT autodiscovery to create HA entities
3. **Find the actual HA entities**: Use `ha_list_entities()` and identify every entity that belongs to the new device. Newly discovered MQTT entities may still use IEEE-based IDs.
4. **Rename and place entities**: For each device entity, use `ha_entity_rename(entity_id="...", new_entity_id="domain.<chosen_name_underscore>_<property>", name="Friendly Name", area_id="chosen_area_id")`
5. **Verify final entity IDs**: Run `ha_list_entities(area=chosen_area)` again and confirm the renamed entities now appear with readable IDs.
6. **Add IEEE to known devices**: Append to `~/.hermes/device_onboarding/known_devices.json`
7. **Notify user of completion** and any remaining manual steps

## Area Assignment

**Prerequisite:** The MQTT integration MUST be configured as a config entry in HA for entity registry operations to work. If entities return 404 on rename/area operations, the MQTT integration is missing.

### Listing Areas

Use the native tool:

```python
ha_list_areas()
```

### Creating a New Area

If the user chooses a room name that does not exist yet, create it with the native tool:

```python
ha_create_area(name="Büro")
```

Use the returned `area_id` for later assignments. Home Assistant normalizes special characters, so `Büro` typically becomes `buero`.

### Assigning Entities to an Area

Assign every entity of the new device with the native tool:

```python
ha_assign_area(entity_id="sensor.xxx_yyy", area_id="buero")
```

### Renaming Entity IDs and Friendly Names

After Zigbee2MQTT rename, Home Assistant MQTT entities can still keep IEEE-based entity IDs. Fix them with the native tool:

```python
ha_entity_rename(
  entity_id="sensor.0xa4c138f531a61971_temperature",
  new_entity_id="sensor.klima_buero_temperature",
  name="Klima Büro Temperatur",
  area_id="buero",
)
```

Use one call per entity. Prefer this combined update path over separate rename and area calls when you already know the final target name and area.

## Scripts

- `scripts/detect_new_devices.py` — Legacy standalone detection script (reads from `current_devices.json`). Not used in the manual flow — the agent calls `ha_zigbee_manage action=list_devices` directly. Kept for reference.
- `known_devices.json` (`~/.hermes/device_onboarding/known_devices.json`) — JSON array of IEEE addresses that have already been onboarded. Updated after each successful onboarding.

## References

- See the `home-assistant` skill for broader HA/Z2M troubleshooting patterns.

## Pitfalls

- **Manual-only trigger** — Do NOT create a cron job for device detection. The user explicitly wants manual trigger only ("Gerät anlernen").
- **Don't rename coordinator** — Always filter out devices with `type: "Coordinator"`.
- **MQTT config entry required** — Z2M devices appearing in `ha_list_entities` but returning 404 on entity registry operations means the MQTT integration is not a config entry. Fix: Einstellungen → Geräte & Dienste → Integration hinzufügen → MQTT.
- **Rename every MQTT entity explicitly** — Zigbee2MQTT rename does not guarantee readable Home Assistant `entity_id` values. Newly discovered MQTT entities can keep IEEE-based IDs until you update them through `ha_entity_rename`.
- **Use native area tools** — `ha_list_areas`, `ha_create_area`, and `ha_assign_area` are available natively. Do not fall back to ad-hoc WebSocket scripts for the normal onboarding flow.
- **Umlauts stripped in area IDs** — HA generates area IDs from display names stripping special chars: "Büro" → `buero`. Always use the returned `area_id` from the API response, not the display name, when assigning entities.
- **Entity discovery delay** — After Z2M rename, HA may need 10-15s to reflect new friendly names via MQTT autodiscovery. Always wait and re-check before assigning entities.
- **MQTT_HOST** — On HAOS, must be `core-mosquitto` not `localhost`.
- **clarify limit** — `clarify` supports max 4 choices + "Other". If more than 4 areas exist, pick the 4 most relevant.
- **German user** — All messages must be in German.
- **Detection script is standalone** — `scripts/detect_new_devices.py` exists but requires paho-mqtt in system Python (not available in cron sandbox). It is NOT used for automatic detection. It can be run manually from the Hermes agent's execute_code if needed.
- **IEEE in discovery topics and entity IDs** — Z2M MQTT discovery topics use the IEEE address as object ID, not friendly name. Newly discovered entities may have IEEE-based entity_ids (e.g., `binary_sensor.0xa4c138e6b83efa09_occupancy`) until you explicitly rename them in HA. Always verify actual entity IDs via `ha_list_entities` before referencing them in automations or scripts.
- **Interview FAILED** — New devices may show `interview_state: "FAILED"` and `type: "Unknown"` if Z2M couldn't identify them. Wait and re-trigger permit_join, then have the user reset the device again. The device may need several pairing attempts. If interview stays FAILED after multiple tries, the device may be unsupported by Z2M.
- **Automation entity verification** — When creating automations triggered by Z2M sensors, ALWAYS verify the actual entity_id via `ha_list_entities` first. Do NOT guess or construct entity IDs from friendly names, because new MQTT entities may use IEEE-based IDs initially.
- **Multiple entities per device** — A typical Z2M device creates multiple HA entities (sensors, selects, numbers, binary sensors). After assigning to area, search the full entity registry by IEEE address to find ALL entities for the device, then assign each to the area with appropriate friendly names. Common hidden entities: `sensor.*_linkquality`, `button.*_identify`, `update.*`, `select.*_effect`, `select.*_power_on_behavior`.
- **Matter label must be unexposed BEFORE removal** — When offboarding a device, ALWAYS check `ha_matter_manage(action="list_exposed")` for any of its entities and unexpose them FIRST. If you remove from Z2M without unexposing, the matter label may persist or re-appear on re-pairing, causing unwanted Alexa exposure.

## Device Offboarding (Removal)

When a user wants to remove ("ablernen") a Zigbee device:

### Step 1: Confirm which device
Use `clarify` to confirm the device. Show the device name, model, and IEEE address.

### Step 2: Check and remove Matter label ⚠️ CRITICAL

**BEFORE removing the device from Z2M, check if any of its entities have the "matter" label.** If a device has the matter label and is removed from Z2M without unexposing first, Alexa will still see it — and when the device is re-paired, it may get the matter label automatically, causing it to leak to Alexa again.

```python
# Check if any entities with the device's keyword have the matter label
ha_matter_manage(action="list_exposed")
```

If any entities of the device are exposed, unexpose them FIRST:

```python
# Unexpose each entity of the device
ha_matter_manage(action="unexpose", entity_id="light.schreibtischlampe_buero")
# Repeat for all entities of the device
```

Only proceed to Step 3 after ALL matter labels are removed.

### Step 3: Remove from Z2M
```python
ha_zigbee_manage(action="remove_device", friendly_name="<ieee_address_or_friendly_name>")
```

This sends a network leave command and removes the device from Z2M. HA will automatically clean up the MQTT autodiscovery entities on the next state refresh.

### Step 4: Update known_devices.json
Remove the device's IEEE address from `~/.hermes/device_onboarding/known_devices.json`.

### Step 5: Remind user
Tell the user to factory-reset the physical device (hold reset button ~10s) if they want to pair it elsewhere. Otherwise it may reconnect automatically.

**Note:** HA removes MQTT autodiscovery entities automatically after Z2M device removal. Manual entity cleanup via WebSocket API is usually not needed.

### Pitfall: Matter label persists after re-pairing
⚠️ If a device had the "matter" label before removal, and is not unexposed first, the label may carry over or re-appear when the device is paired again. This causes the device to be immediately exposed to Alexa/Matter without user consent. **Always unexpose before removing.**

## See Also

- `home-assistant` skill — parent skill with HA/Z2M management, troubleshooting, and the `references/ha-websocket-api.md` for full WebSocket patterns
