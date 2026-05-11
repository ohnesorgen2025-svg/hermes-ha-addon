# AGENTS.md — Hermes Agent HA Add-on (Fork & Strip)

## Projekt-Kontext
Fork von github.com/WolframRavenwolf/hermes-ha-addon.
Ziel: Radikal abspecken für Raspberry Pi 4B (4 GB RAM) bei Stefans Vater.
Nur Gateway-Modus, Ollama Cloud, Telegram. Kein Browser, kein Terminal, kein nginx.

## Vorgehen

### Phase 1: Aufräumen
1. Alle Dateien identifizieren die zu ttyd, nginx, landing-page,
   browser/playwright, WhatsApp-Bridge gehören
2. Diese Dateien LÖSCHEN
3. Dockerfile STRIPPEN:
   - Go, Homebrew, Chromium, agent-browser, ttyd, nginx RAUS
   - bat, fd-find, gh, htop, nano, vim, imagemagick, ghostscript RAUS
   - Python, Node.js, uv, ripgrep, ffmpeg, jq, git, curl BEHALTEN
   - Hermes Install: NUR base install, KEIN [all] extra
4. config.yaml VEREINFACHEN:
   - Alte Options entfernen (git_token, enable_terminal, enable_api,
     hass_url, homeassistant_token, hermes_home, env_vars)
   - Neue Options: ollama_api_key, ollama_model, telegram_bot_token,
     access_password, auto_update
5. Commit: "feat: strip bloat — remove browser, terminal, nginx"

### Phase 2: Anpassen
1. run.sh NEU SCHREIBEN:
   - Nur: Config lesen → .env schreiben → config.yaml (first run) →
     exec hermes gateway run
   - Kein nginx start, kein ttyd start, kein tmux
   - Telegram Bot Token in .env wenn gesetzt
2. DOCS.md NEU SCHREIBEN
3. README.md ANPASSEN
4. Commit: "feat: minimal run.sh with ollama-cloud + telegram"

### Phase 3: Testen
1. Docker Image lokal bauen (amd64)
2. Container starten mit Test-Config
3. Prüfen: hermes gateway run startet ohne Fehler
4. Prüfen: ollama-cloud Provider funktioniert
5. Prüfen: Image-Größe < 500MB

## Regeln
1. KEIN [all] pip extra — nur was Gateway + HA + Telegram braucht
2. .env wird bei JEDEM Start neu geschrieben (Config-Updates)
3. config.yaml wird NUR geschrieben wenn NICHT vorhanden (User-Edits schützen)
4. SUPERVISOR_TOKEN aus Environment, NICHT hardcoden
5. HERMES_HOME=/config/.hermes (Original-Pfad beibehalten)
6. Multi-arch: aarch64 + amd64
7. Conventional Commits
8. Slug NIEMALS ändern

## Was NICHT angefasst werden darf
- Add-on Slug in config.yaml
- Persistenz-Pfad /config/.hermes/
- SUPERVISOR_TOKEN Mechanismus
- Hermes git-clone + venv Grundstruktur

## Was GELÖSCHT werden muss
- Alles zu ttyd (config, scripts, binary install)
- Alles zu nginx (configs, templates, certs)
- Alles zu landing-page / HTML UI
- Chromium / Playwright / agent-browser Install
- WhatsApp-Bridge (Node.js Puppeteer)
- Go / Homebrew Install
- TLS Zertifikats-Generierung
- start-hermes Wrapper Scripts
- tmux Config und Session-Management
- Alle Dev-Tools die nicht für Hermes Gateway nötig sind:
  bat, fd-find, gh, htop, nano, vim, imagemagick, ghostscript,
  command-not-found, bash-completion

## Was BEHALTEN werden soll
- Hermes git clone + uv venv + install Logik
- auto_update / git pull Logik
- .env Schreib-Logik (adaptieren für unsere Options)
- Persistenz-Struktur
- bashio Integration
- Arch-Support (aarch64 + amd64)

## Config-Schema

    options:
      ollama_api_key: ""
      ollama_model: "hermes3:latest"
      telegram_bot_token: ""
      access_password: ""
      auto_update: false
    schema:
      ollama_api_key: str
      ollama_model: str
      telegram_bot_token: str
      access_password: str
      auto_update: bool

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

## Build und Test

Lokal bauen (amd64):

    cd hermes_agent
    docker build -t hermes-ha-addon-slim .
    docker run -it --rm \
      -e SUPERVISOR_TOKEN=test \
      -v $(pwd)/test-config:/config \
      hermes-ha-addon-slim

Image-Größe prüfen:

    docker images hermes-ha-addon-slim

Auf HA testen:
1. Fork auf GitHub pushen
2. HA: Settings → Add-ons → Add-on Store → ⋮ → Repositories
3. Fork-URL eintragen → Add
4. Hermes Agent installieren → Config → Start → Logs prüfen

## Referenzen
- Original Add-on: https://github.com/WolframRavenwolf/hermes-ha-addon
- Hermes Agent: https://github.com/NousResearch/hermes-agent
- Hermes Docker: https://hermes-agent.nousresearch.com/docs/user-guide/docker
- Hermes HA: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/homeassistant
- Hermes Providers: https://hermes-agent.nousresearch.com/docs/integrations/providers
- Hermes Telegram: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram
- Ollama Cloud: https://ollama.com/blog/cloud-models
- HA Add-on Docs: https://developers.home-assistant.io/docs/apps/configuration/