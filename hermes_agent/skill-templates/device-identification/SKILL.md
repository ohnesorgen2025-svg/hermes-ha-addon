---
name: device-identification
description: "Identify an unknown Home Assistant device by briefly listening for state changes after the user triggers it, with responsive German Telegram feedback."
version: 1.1.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Smart-Home, Home-Assistant, Device-Identification, Telegram]
---

# Device Identification

Identify a physical smart-home device when the user can touch or trigger it but does not know which Home Assistant entity it belongs to.

## When to Use

Use this skill when the user says one of these or similar phrases:

- "Lauschen"
- "Hermes, lauschen"
- "Welches Gerät ist das?"
- "Gerät identifizieren"
- "Finde dieses Gerät"
- "Ich habe hier ein unbekanntes Gerät"

## Core Behavior

This skill listens to Home Assistant state changes, not to audio.

Default listening window: 10 seconds.
Maximum listening window: 20 seconds.

For the default flow, split listening into two short windows so Telegram feels responsive.

Start with a short German confirmation:

> Ich lausche jetzt. Bitte drücke, bewege oder schalte das Gerät direkt nach dieser Nachricht.

Then call the first short observation:

```python
ha_observe_changes(duration_seconds=5)
```

If this first call finds a clear candidate, report it immediately. If it finds no candidate, send this German interim message before continuing:

> Noch nichts Eindeutiges gesehen. Ich lausche noch 5 Sekunden weiter. Bitte löse das Gerät jetzt nochmal aus.

Then call the second short observation:

```python
ha_observe_changes(duration_seconds=5)
```

Evaluate the combined evidence from both observations. If both windows return candidates, prefer the highest-scoring intentional action using the noise rules below.

Use a longer window only when the user explicitly asks for more time:

```python
ha_observe_changes(duration_seconds=15)
```

Do not use windows longer than 20 seconds.

## Result Handling

### No Candidate

If `best_candidate` is null or `event_count` is 0, say:

> Ich habe keine eindeutige Änderung gesehen. Bitte versuche es nochmal und löse das Gerät direkt nach meiner Nachricht aus.

Offer to listen again.

### One Strong Candidate

If there is one clear high-scoring candidate, answer with:

- friendly name if available
- `entity_id`
- state transition
- likely device type if obvious from domain or entity name
- area if available in attributes or from later lookup

Example:

> Das dürfte `binary_sensor.fenster_bad_contact` sein. Der Zustand wechselte von `off` auf `on`. Das sieht nach einem Fenster-/Türkontakt aus.

Then ask whether the user wants to rename it or assign it to a room.

### Multiple Candidates

If multiple candidates are plausible, show the top 3 only. Keep the answer compact and ask which one fits.

If the result contains `cascade.cascade_detected: true`, explain that one physical controller probably triggered several downstream entities. Prefer candidates with `likely_controller_for_cascade`, `controller_action_entity`, `button_or_event`, or entity IDs ending in `_action`, `_click`, or `_button`. Treat many simultaneous `light` or `switch` changes as likely follow-up effects unless the user says they touched one of those actuators directly.

Example:

> Ich habe mehrere mögliche Treffer gesehen:
> 1. `binary_sensor.fenster_bad_contact` (`off` -> `on`)
> 2. `sensor.flur_button_action` (`idle` -> `single`)
> 3. `switch.steckdose_regal` (`off` -> `on`)
>
> Welches davon hast du gerade ausgelöst?

Dimmer cascade example:

> Ich sehe eine Kaskade: Ein Bedienelement hat vermutlich mehrere Lampen ausgelöst. Der wahrscheinlichste Auslöser ist `sensor.dimmer_wohnzimmer_action` (`rotate_right`). Die Lampenänderungen wirken wie Folgeeffekte.

## Noise Rules

Prefer these as intentional actions:

- `button`, `input_button`, `event`, `_action`, `_click`, or `_button` entities
- `binary_sensor` contact or motion changes
- direct `switch`, `light`, `cover`, `lock`, `fan` changes when there is no controller/action entity in the same observation window
- strong transitions like `off -> on`, `on -> off`, `closed -> open`, `open -> closed`

When a dimmer, remote, wall switch, or scene controller changes many lamps at once, prefer the controller/action entity over the lamp entities.

Treat these as low-confidence background noise unless they are the only clue:

- battery
- linkquality / RSSI / signal strength
- tiny temperature or humidity changes
- power or energy telemetry
- update, weather, sun, calendar, person, zone, device tracker entities

## Follow-up Actions

After identifying a device, the user may want to:

- rename the entity with `ha_entity_rename`
- assign it to an area with `ha_assign_area`
- expose it to Matter/Alexa with `ha_matter_manage`
- run the normal onboarding skill if it is a newly paired device

Always ask before changing names, areas, labels, or exposure.
