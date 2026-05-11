# Hermes Agent HA Add-on — Design (Fork & Strip)

## Basis
Fork von github.com/WolframRavenwolf/hermes-ha-addon (v1.0.0, MIT License).
Upstream hat 103 Commits, ein Contributor, Shell/Dockerfile/Smarty-Templates.

## Architektur

### Original (Wolfram): 3 Prozesse

nginx → ttyd (hermes) → tmux session
nginx → ttyd (terminal) → tmux session
nginx → hermes gateway run (API + Messaging)

### Unser Fork: 1 Prozess

run.sh → hermes gateway run

Das ist alles. Kein nginx, kein ttyd, kein tmux.

## Config-Schema (HA UI)

| Option | Typ | Default | Beschreibung |
|--------|-----|---------|--------------|
| ollama_api_key | str | "" | Ollama Cloud API Key |
| ollama_model | str | "hermes3:latest" | Cloud-Modell |
| telegram_bot_token | str | "" | Telegram Bot Token |
| access_password | str | "" | Hermes API Key (Port 8443) |
| auto_update | bool | false | Hermes bei Restart updaten |

## Dockerfile-Strategie

Wolframs Dockerfile installiert — wir strippen:

RAUS: Go, Homebrew, Chromium, agent-browser, ttyd, nginx,
bat, fd-find, gh, htop, nano, vim, imagemagick, ghostscript

BEHALTEN: Python 3.11, Node.js 22, uv, ripgrep, ffmpeg, jq, git, curl

Ziel: Image-Größe von ~2GB+ auf unter 500MB.

## run.sh Logik

1. bashio::config lesen (ollama_api_key, ollama_model, telegram_bot_token)
2. SUPERVISOR_TOKEN aus Environment nehmen
3. ~/.hermes/.env schreiben (bei jedem Start, für Config-Updates)
4. ~/.hermes/config.yaml schreiben (NUR wenn nicht vorhanden)
5. exec hermes gateway run

## Hermes Config (first-run generated)

    model:
      provider: ollama-cloud
      model: hermes3:latest
    platforms:
      homeassistant:
        enabled: true
      telegram:
        enabled: true

## .env (bei jedem Start geschrieben)

    OLLAMA_API_KEY=<from config>
    HASS_TOKEN=<SUPERVISOR_TOKEN>
    HASS_URL=http://supervisor/core
    TELEGRAM_BOT_TOKEN=<from config, wenn gesetzt>

## Persistenz (unverändert vom Original)

    /config/.hermes/
    ├── hermes-agent/          # Git clone + venv
    ├── memories/              # Long-term memory
    ├── sessions/              # Conversations
    ├── skills/                # Auto-created skills
    ├── .env                   # API keys
    ├── config.yaml            # Hermes config
    └── state.db               # SQLite state

## Update-Sicherheit

1. Base Image nicht auf Patch-Level pinnen
2. Hermes Version pinnbar via git_ref Config-Option
3. Add-on Slug NIEMALS ändern
4. .env bei jedem Start neu schreiben
5. config.yaml nur beim ersten Start schreiben
6. auto_update Option vom Original behalten

## Upstream-Sync Strategie

- Fork behält Git-History
- Upstream-Changes selektiv cherry-picken wenn relevant
- Wolframs Additions (ttyd, nginx, browser) werden nie gemerged
- Hermes Install/Update-Logik kann upstream-Updates übernehmen