# Hermes Agent HA Add-on (Fork & Strip)

## Vision
Fork von WolframRavenwolf/hermes-ha-addon, radikal abgespeckt für einen
Raspberry Pi 4B (4 GB RAM) bei Stefans Vater.

Ziel: Schlankes, sicheres Add-on das Hermes Agent im Gateway-Modus startet.
LLM via Ollama Cloud. Messaging via Telegram. HA-Steuerung via HASS_TOKEN.

## Was wir vom Original behalten
- Hermes Install + venv-Logik
- HA Supervisor Token Integration
- Persistenz-Struktur (~/.hermes/)
- Add-on config.yaml Grundstruktur
- Gateway-Start-Logik

## Was wir rauswerfen
- Playwright / Chromium / agent-browser (zu heavy für Pi, Sicherheitsrisiko)
- WhatsApp-Bridge (Node.js Puppeteer Overhead, nicht benötigt)
- ttyd / Web-Terminal (2x ttyd Prozesse, tmux Sessions)
- nginx (nur nötig für Terminal/Ingress Routing)
- Self-Modifiable Source Flag
- HTTPS / TLS Zertifikats-Management
- Homebrew (Linuxbrew)
- Go Toolchain
- bat, fd-find, gh, htop, nano, vim, imagemagick, ghostscript
- Multi-Profile Support (hermes_home Option)
- SSH-Zugang über Docker-Exec Dokumentation

## Was wir anpassen
- Default-Provider: ollama-cloud statt OpenRouter
- Config-Schema: nur ollama_api_key, ollama_model, telegram_bot_token, access_password
- Dockerfile: Minimal-Install ohne [all], kein Playwright, kein Browser
- Ein Prozess: nur hermes gateway run (kein nginx, kein ttyd)
- Port 8443 nur für Hermes API (optional, für externe Clients)

## Was wir hinzufügen
- telegram_bot_token als eigene Config-Option (statt über env_vars)
- Ollama Cloud als vorkonfigurierter Provider

## Zielplattform
- Raspberry Pi 4B (aarch64), 4 GB RAM, HAOS 17.3+
- Auch amd64 für Dev/Test

## Nicht-Ziele (v1)
- Kein Web-UI im Add-on
- Kein Browser-Automation
- Kein lokales LLM