# Architektur des Hermes-Addon-Systems

Dieses Dokument beschreibt die verifizierte Architektur des Home-Assistant-Addons rund um Hermes. Es basiert auf dem aktuell geprüften Stand der Repos und der ausgeführten Fixes, nicht auf Produkttext oder Annahmen.

## Status, Versionierung und Pflege

Dieses Dokument hat bewusst keine eigene SemVer. Maßgeblich ist immer der Git-Stand des Repos, in dem diese Datei liegt.

Für dieses System bedeutet das konkret:

- die technische Wahrheit für Addon-Auslieferung und Integration liegt im jeweiligen Commit des Wrapper-Repos
- Änderungen am gepinnten Runtime-Commit, an Addon-Version, Update-Pfad, Tool-Exposition, Approval-Verhalten, Skill-Sync oder anderen architekturprägenden Flows müssen in dieser Datei im selben Change mitgezogen werden
- wenn sich nur Implementierungsdetails ohne Architekturwirkung ändern, braucht die Datei nicht künstlich angepasst zu werden

Pflegeregel:

- `ARCHITECTURE.md` ist ein lebendes Wartungsdokument und muss bei jeder relevanten Architekturänderung aktiv erweitert oder korrigiert werden
- ein Change ist aus Dokumentationssicht unvollständig, wenn er die Systemarchitektur verändert, aber diese Datei unverändert lässt

## 1. Überblick

Das System ist ein Home-Assistant-Addon, das einen Hermes-Agenten als Gateway-Agent in Home Assistant betreibt. Der typische Betriebspfad ist:

- Home Assistant startet das Addon-Container-Image.
- Das Wrapper-Skript bootstrapped den Hermes-Runtime-Fork in `/config/.hermes/hermes-agent`.
- Danach startet es `hermes gateway run`.
- Benutzer interagieren typischerweise über Telegram mit Hermes.
- Der Agent kann Home Assistant lesen und steuern, Skills laden, Tools ausführen und Modellanbieter wie Ollama Cloud oder andere OpenAI-kompatible Backends verwenden.

Im aktuellen Addon-Stand ist der Default-Provider im Addon-UI `ollama-cloud`, siehe [hermes_agent/config.yaml](hermes_agent/config.yaml). Das Addon kann aber auch andere Provider-Keys in die Hermes-Umgebung schreiben.

Kurz gesagt: Das Addon ist die Integrationsschicht zwischen Home Assistant, dem gepinnten Hermes-Fork und einer persistenten Laufzeitumgebung unter `/config/.hermes`.

## 2. Die drei Bausteine

### 2.1 `hermes-ha-addon` (Wrapper)

Dieses Repo ist die Integrations- und Auslieferungsschicht für Home Assistant.

Wichtige Dateien:

- [hermes_agent/run.sh](hermes_agent/run.sh): Startlogik des Addons
- [hermes_agent/config.yaml](hermes_agent/config.yaml): Addon-Metadaten, Version, Optionen, Schema
- [hermes_agent/Dockerfile](hermes_agent/Dockerfile): Addon-Image mit Systempaketen und Wrapper-Dateien
- [hermes_agent/scripts/sync-skills.sh](hermes_agent/scripts/sync-skills.sh): Read-only-Sync der Runtime-Skills ins Spiegel-Repo

Verifizierte Aufgaben des Wrappers:

- liest Addon-Optionen aus `/data/options.json`
- schreibt daraus `/config/.hermes/.env`
- pflegt `/config/.hermes/config.yaml`
- klont oder aktualisiert den Hermes-Fork aus `HERMES_REPO`
- pinnt standardmäßig auf `PINNED_HERMES_REF`
- überschreibt den Pin nur, wenn `HERMES_REF` gesetzt ist oder `auto_update: true` aktiv ist
- installiert ein Python-Venv im persistenten Runtime-Verzeichnis
- startet am Ende `hermes gateway run`
- synchronisiert mitgelieferte Skill-Templates nach `/config/.hermes/skills`
- startet zusätzlich den täglichen Skills-Sync-Cronjob

Wichtige Laufzeitpfade aus [hermes_agent/run.sh](hermes_agent/run.sh):

- `HERMES_HOME=/config/.hermes`
- Runtime-Checkout: `/config/.hermes/hermes-agent`
- aktive Skills: `/config/.hermes/skills`
- Skill-Backups: `/config/.hermes/skill-backups`
- Geräte-Onboarding-Daten: `/config/.hermes/device_onboarding`

### 2.2 `hermes-agent` (Fork)

Dieses Repo enthält die eigentliche Agent-Runtime.

Wichtige Dateien:

- [run_agent.py](../hermes-agent/run_agent.py): Agent-Loop und Conversation-Ausführung
- [model_tools.py](../hermes-agent/model_tools.py): Discovery und Orchestrierung der Tools
- [toolsets.py](../hermes-agent/toolsets.py): Exposition der Tools über Toolsets
- [tools/homeassistant_tool.py](../hermes-agent/tools/homeassistant_tool.py): Home-Assistant-Tooling
- [tools/approval.py](../hermes-agent/tools/approval.py): zentrales Approval-System
- [tools/memory_tool.py](../hermes-agent/tools/memory_tool.py): Memory-Store und Write-Gates

Verifizierte Laufzeitmechanik:

- `run_conversation()` in [run_agent.py](../hermes-agent/run_agent.py) führt die Hauptschleife aus
- die Runtime nutzt OpenAI-formatierte Nachrichten (`system`, `user`, `assistant`, `tool`)
- `model_tools.py` importiert die selbstregistrierenden Tool-Module und baut daraus die tatsächlich exponierte Toolliste
- die Tool-Registry ist generisch; was das Modell wirklich sieht, wird über Toolsets gesteuert

### 2.3 `hermes-state` (Spiegel)

`hermes-state` ist ein privates Git-Repo als read-only Spiegel der zur Laufzeit generierten Skills. Es ist kein Laufzeitbestandteil des Agenten.

Ziel:

- Reviewer oder Maintainer können sehen, welche Skills Hermes in `/config/.hermes/skills/` aktuell benutzt oder generiert
- der Spiegel wird vom Wrapper per Script gepusht, nicht von Hermes selbst
- Hermes erhält dafür keinen Git-Zugang und keine Git-Credentials

Der aktuelle Default-Pushpfad des Wrappers ist in [hermes_agent/scripts/README.md](hermes_agent/scripts/README.md) dokumentiert als:

- `git@github.com:ohnesorgen2025-svg/hermes-state.git`

## 3. Tool-System

### 3.1 Registrierung und Exposition

Das Tool-System ist zweistufig:

1. Registrierung:
   Tool-Dateien rufen auf Modulebene `registry.register(...)` auf.
2. Exposition:
   [toolsets.py](../hermes-agent/toolsets.py) entscheidet, welche registrierten Tools in welchem Toolset sichtbar sind.

Verifizierte Kernaussagen aus [model_tools.py](../hermes-agent/model_tools.py) und [toolsets.py](../hermes-agent/toolsets.py):

- Tools registrieren sich selbst über `tools.registry`
- `model_tools.py` triggert die Discovery dieser Tool-Module
- die Standard-Toolsets für CLI und Messaging hängen an `_HERMES_CORE_TOOLS`
- `execute_code` wurde aus `_HERMES_CORE_TOOLS` entfernt und ist damit nicht mehr standardmäßig exponiert
- explizite Opt-in-Toolsets wie `code_execution` können es weiterhin enthalten

### 3.2 Home-Assistant-Tools

Im aktuellen Fork sind folgende `ha_*`-Tools registriert in [tools/homeassistant_tool.py](../hermes-agent/tools/homeassistant_tool.py):

- `ha_list_entities`
- `ha_get_state`
- `ha_detect_capabilities`
- `ha_observe_changes`
- `ha_list_areas`
- `ha_create_area`
- `ha_assign_area`
- `ha_supervisor_manage`
- `ha_update_manage`
- `ha_admin_diagnose`
- `ha_config_read`
- `ha_config_write`
- `ha_config_reload`
- `ha_dashboard_manage`
- `ha_integration_manage`
- `ha_entity_rename`
- `ha_list_services`
- `ha_call_service`
- `ha_automation_manage`
- `ha_zigbee_manage`
- `ha_matter_manage`

Diese Tools sind im Core-Toolset des Addon-Betriebs sichtbar, weil sie in `_HERMES_CORE_TOOLS` in [toolsets.py](../hermes-agent/toolsets.py) enthalten sind.

## 4. Approval-System

### 4.1 Zentrales Gate

Das zentrale Approval-System sitzt in [tools/approval.py](../hermes-agent/tools/approval.py). Der Terminal-Pfad läuft darüber, und Home-Assistant-Destruktivaktionen verwenden denselben Mechanismus über `_check_ha_tool_approval(...)` in [tools/homeassistant_tool.py](../hermes-agent/tools/homeassistant_tool.py).

Die Approval-Modi sind verifiziert in [tools/approval.py](../hermes-agent/tools/approval.py):

- `manual`
- `smart`
- `off`

Zusätzlich gibt es einen separaten Cron-Modus:

- `deny`
- `approve`

### 4.2 Was aktuell gegated ist

Verifizierte gegatete oder hart blockierte Klassen:

- Terminal-Kommandos, die von `detect_dangerous_command()` als gefährlich erkannt werden
- HA-Supervisor-Aktionen wie Stop, Restart, Uninstall über `ha_supervisor_manage`
- Integrations-Entfernung über `ha_integration_manage`
- Zigbee-Entfernung über `ha_zigbee_manage`
- Entity-Registry-Änderungen über `ha_entity_rename`
- Automation Create/Update/Delete über `ha_automation_manage`
- Core-Config-Schreiben über `ha_config_write`
- `ha_call_service` für `homeassistant.restart` und `homeassistant.stop`

Zusätzlich gibt es in [tools/homeassistant_tool.py](../hermes-agent/tools/homeassistant_tool.py) eine harte Blocklist für besonders gefährliche HA-Service-Domains wie:

- `shell_command`
- `command_line`
- `python_script`
- `pyscript`
- `hassio`
- `rest_command`

Wirkung: Nicht jede gefährliche Aktion wird nur „bestätigt“, manches wird an der Domain-Ebene direkt gesperrt.

## 5. Skill-System

### 5.1 Mitgelieferte Skills

Der Wrapper bringt Skill-Templates im Addon-Image mit. Diese liegen im Repo unter:

- [hermes_agent/skill-templates](hermes_agent/skill-templates)

Beim Start kopiert [hermes_agent/run.sh](hermes_agent/run.sh) diese nach:

- `/config/.hermes/skill-templates`

und synchronisiert sie als aktive Skills nach:

- `/config/.hermes/skills`

Wenn bereits aktive Skill-Verzeichnisse existieren und vom mitgelieferten Stand abweichen, werden sie vorher nach `/config/.hermes/skill-backups` gesichert.

Die Synchronisation verwendet einen Hash-Marker:

- `.addon-managed-sha256`

### 5.2 Zur Laufzeit generierte Skills

Hermes kann zur Laufzeit Skills im persistenten Skill-Verzeichnis schreiben. Der relevante operative Pfad ist ebenfalls:

- `/config/.hermes/skills`

Das ist derselbe Baum, den die Skills-Sync-Bridge ins Spiegel-Repo kopiert.

## 6. Memory-System

Das Memory-System liegt im Fork und ist prompt-sensitiv. Es ist kein beliebiger Notizzettel.

Verifizierte Eigenschaften aus [tools/memory_tool.py](../hermes-agent/tools/memory_tool.py):

- Memory-Einträge werden in Dateien unter dem Memory-Verzeichnis persistiert
- Memory ist begrenzt und kuratiert
- es gibt einen Scan vor dem Schreiben (`_scan_memory_content`)
- geblockt werden unsichtbare Unicode-Zeichen, Injektions-/Exfiltrationsmuster und Home-Assistant-Entity-IDs

Die spezifische HA-Regel lautet im Code sinngemäß:

- Entity-IDs sind aus HA live ableitbar und gehören nicht in Memory

Das ist ein Write-Gate, damit keine unnötigen oder manipulativen Runtime-Fakten in den Systemprompt eingeschleust werden.

## 7. Skills-Sync-Bridge

### 7.1 Ziel und Prinzip

Die Bridge ist eine wrapper-gesteuerte Git-Spiegelung der aktiven Runtime-Skills.

Wichtige Eigenschaften:

- Hermes selbst pusht nicht
- der Wrapper pusht
- Zugriff erfolgt per dediziertem Deploy-Key
- es gibt einen harten Secret-Scan vor jedem Commit und Push
- es wird nur bei echtem Diff committet

### 7.2 Implementierung

Die Implementierung sitzt in:

- [hermes_agent/scripts/sync-skills.sh](hermes_agent/scripts/sync-skills.sh)

Der tägliche Trigger wird in [hermes_agent/run.sh](hermes_agent/run.sh) eingerichtet:

- Cronfile: `/etc/cron.d/hermes-skill-sync`
- Default-Schedule: `17 3 * * *`
- Logfile: `/config/.hermes/logs/skill-sync.log`

Manueller Trigger:

- `sync-skills`

### 7.3 Secret-Scan

Der Scan ist fail-closed. Wenn er anschlägt, beendet das Script den Lauf mit Exit-Code `10` und erstellt keinen Commit.

Aktueller verifizierter Zuschnitt:

- blockt echte private Schlüsseldateien und PEM/SSH-Key-Dateinamen
- blockt echte Token-Muster in realistischer Voll-Länge
- blockt Literal-Assignments mit Secret-Feldnamen nur dann, wenn rechts ein echter Wert und kein Beispiel steht
- blockt öffentliche IPv4-Adressen

Explizit nicht blockiert:

- private oder localhost-IP-Adressen
- Platzhalter wie `REDACTED`, `<TOKEN>`, `xx...xxxx`, `your-api-key`
- Umgebungsvariablen-Referenzen wie `os.getenv(...)` oder `${API_TOKEN}`
- reine Variablennamen oder Typannotationen ohne echten Secretwert

Die operative Doku dazu liegt in [hermes_agent/scripts/README.md](hermes_agent/scripts/README.md).

## 8. Build- und Update-Ablauf

Der derzeit etablierte Update-Pfad ist:

1. Fix im Hermes-Fork implementieren und testen.
2. Commit im Fork nach `origin/main` pushen.
3. Im Wrapper den Pin in [hermes_agent/run.sh](hermes_agent/run.sh) auf den neuen Runtime-Commit setzen.
4. Addon-Version in [hermes_agent/config.yaml](hermes_agent/config.yaml) erhöhen.
5. Changelog in [hermes_agent/CHANGELOG.md](hermes_agent/CHANGELOG.md) ergänzen.
6. Wrapper nach `origin/main` pushen.
7. In Home Assistant das Addon aktualisieren.

Das ist wichtig, weil Home Assistant nicht auf den Fork-Commit selbst schaut, sondern auf die Addon-Version aus dem Wrapper.

Versionierungsrelevant in diesem Ablauf sind zwei Ebenen:

- der Runtime-Stand wird technisch über den Git-Pin `PINNED_HERMES_REF` in [hermes_agent/run.sh](hermes_agent/run.sh) bestimmt
- die für Home Assistant sichtbare ausrollbare Version wird über `version` in [hermes_agent/config.yaml](hermes_agent/config.yaml) bestimmt

Praktische Regel:

- Runtime-Fix ohne Wrapper-Pin-Update bleibt im Addon wirkungslos
- Wrapper-Pin-Update ohne sinnvolle Addon-Versionsanhebung ist operativ schwer nachvollziehbar
- wenn einer dieser beiden Punkte geändert wird und dadurch das reale Systemverhalten anders ist, muss auch [ARCHITECTURE.md](ARCHITECTURE.md) geprüft und bei Bedarf angepasst werden

## Warum dieses Dokument im Wrapper-Repo liegt

Dieses Dokument gehört sinnvollerweise ins Repo [ARCHITECTURE.md](ARCHITECTURE.md) im Root von `hermes-ha-addon`, nicht in `hermes-agent`.

Grund:

- Das beschriebene System besteht aus drei Repos und ihrer Kopplung.
- Der Wrapper ist die Integrations- und Auslieferungsschicht, an der diese Kopplung sichtbar und steuerbar wird.
- Ein fremder Entwickler, der das Addon übernimmt, startet praktisch immer im Wrapper-Repo, nicht im Runtime-Fork allein.

Der Fork selbst hat bereits eigene Entwicklungsdokumentation. Dieses Dokument beschreibt bewusst die darüberliegende Addon-Systemarchitektur.