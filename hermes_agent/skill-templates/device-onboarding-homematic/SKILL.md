---
name: device-onboarding-homematic
description: "German Homematic/HmIP onboarding through Home Assistant: find install mode entities, start pairing, detect new entities, rename, and assign rooms."
version: 1.0.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Smart-Home, Homematic, HmIP, Home-Assistant, Onboarding]
---

# Homematic Device Onboarding

Use this skill when the user wants to add, pair, rename, or place a Homematic, HomeMatic, HmIP, or BidCos device.

## Core Rules

- All messages to the user must be in German.
- Do not ask for openCCU web UI credentials if Homematic is already present in Home Assistant.
- Do not start install mode if the Homematic/HomeMaticIP Local integration is missing.
- Prefer the interface that matches the physical hardware. With `HM-MOD-RPI-PCB`, prefer `BidCos-RF`.
- Use Home Assistant entities and services, not direct CCU login flows, for normal onboarding.

## Preflight

Start with:

```python
ha_detect_capabilities()
```

Required before continuing: Homematic or HomeMaticIP Local integration in Home Assistant Core with install-mode entities.

If missing, stop and say:

> Die Homematic-Integration ist in Home Assistant noch nicht eingerichtet. Bitte richte zuerst Homematic bzw. HomematicIP Local in Home Assistant ein. Danach kann ich den Anlernmodus über Home Assistant starten.

## Discover Install Mode Entities

Inspect available entities:

```python
ha_list_entities(domain="button")
ha_list_entities(domain="sensor")
ha_list_entities(domain="binary_sensor")
```

Find the install-mode button and duration/status sensor by searching entity IDs, friendly names, and attributes for:

- `install_mode`
- `anlernmodus`
- `homematic`
- `bidcos_rf`
- `hmip`

Use `ha_get_state()` when needed to inspect attributes and confirm which button controls install mode and which sensor reflects duration or state.

If multiple candidates exist, choose the one that clearly belongs to the Homematic integration and the interface the hardware supports.

## Start Install Mode

Press the discovered install-mode button:

```python
ha_call_service(domain="button", service="press", entity_id="...")
```

Immediately tell the user:

> ✅ Anlernmodus ist jetzt aktiv. Bitte versetze das Homematic-Gerät jetzt in den Anlernmodus.

Keep the install window open and continue checking for a new device.

## Detect the New Device

Before and after install mode, compare Home Assistant entities and device context. Poll until a new Homematic device appears or the install window ends.

Useful checks:

```python
ha_list_entities()
ha_get_state(entity_id="...")
```

When a new device is found, continue with room assignment and entity rename. If no device appears, say that Home Assistant did not report a new Homematic device and ask the user to retry the physical pairing step.

## Room Assignment

List areas:

```python
ha_list_areas()
```

Use `clarify`:

- question: "🏠 Wohin soll das Gerät? Wähle einen Raum:"
- choices: short room labels such as ["wohnzimmer", "kuche", "schlafzimmer", "buero"]

If Home Assistant has more than 4 areas, do not guess four rooms silently. First show a compact German room overview grouped by floor or alphabetically, then ask the user to type the room name from that list. After the user chooses a room, continue directly; only use `clarify` again if several room names are genuinely ambiguous.

Example:

> Ich habe mehr als vier Räume gefunden: Arbeitszimmer, Bad, Büro, Flur, Küche, Schlafzimmer, Wohnzimmer. Für welchen Raum ist das Gerät? Schreib bitte den Raumnamen aus der Liste.

If the user types a new room name, create it:

```python
ha_create_area(name="Büro")
```

Use the returned `area_id` for assignments.

## Name Assignment

Suggest a readable name using `funktion.raum`. Inspect existing entities in the room first to avoid duplicate suggestions.

```python
ha_list_entities(area="buero")
```

Prefer specific names when a generic one already exists, for example `heizung.buero`, `fenster.buero`, `schalter.buero_tuer`, or `klima.buero_2`.

For entity IDs and suggested technical names, normalize German display names before composing `funktion.raum`: `ä -> ae`, `ö -> oe`, `ü -> ue`, `Ä -> ae`, `Ö -> oe`, `Ü -> ue`, `ß -> ss`, spaces and hyphens to `_`, then lowercase ASCII. Example: room `Büro` should produce `buero`, not `buro`.

Use `clarify` with the suggested name and "Anderer Name".

If the user replies with free text like `ok`, `okay`, `ja`, `passt`, `bestätigen`, or `nimm den Vorschlag` while the suggested name is visible, treat that as confirmation of the suggested name and continue. Do not restart the same `clarify` prompt or wait for another button press.

After a suggested name is confirmed, immediately continue to the summary/confirmation step. Do not open another name-selection `clarify` unless the user chose "Anderer Name" or typed a different name.

## Apply Changes

After user confirmation:

1. Resolve or create the area.
2. Find every entity that belongs to the new Homematic device.
3. Rename entities and assign area with:

```python
ha_entity_rename(
  entity_id="sensor.old_entity",
  new_entity_id="sensor.klima_buero_temperature",
  name="Klima Büro Temperatur",
  area_id="buero",
)
```

4. Verify final entities with `ha_list_entities(area="buero")`.
5. Tell the user what was changed and mention any entity that could not be renamed or assigned.

## Pitfalls

- **No CCU credentials** — do not ask for openCCU username/password in the normal flow.
- **Install-mode entity names vary** — inspect entities dynamically instead of hardcoding one button ID.
- **Interface matters** — with classic BidCos hardware, prefer `BidCos-RF` over an HmIP-only interface.
- **Do not claim success without verification** — confirm new entities appeared and entity registry updates succeeded.
- **German user** — all messages must be in German.
