# Hermes Agent Add-on

Minimal Home Assistant add-on for running Hermes Agent in gateway mode.

This fork is stripped for small Home Assistant hosts such as a Raspberry Pi 4B. It runs one process only: `hermes gateway run`. There is no browser automation, no web terminal, no nginx proxy, and no bundled dashboard.

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `ollama_api_key` | | Ollama Cloud API key. Written to `/config/.hermes/.env` on every start. |
| `ollama_model` | `hermes3:latest` | Ollama Cloud model used in the first-run Hermes config. |
| `telegram_bot_token` | | Telegram bot token. Written to `.env` when set. |
| `access_password` | | Optional Hermes Gateway API key for external clients. |
| `auto_update` | `false` | Pull latest Hermes Agent source on restart. |

Home Assistant access uses the Supervisor token from the add-on environment. Do not configure or hardcode a Home Assistant token yourself.

## Runtime Behavior

On every start the add-on:

1. Reads the Home Assistant add-on options.
2. Ensures `/config/.hermes` exists.
3. Rewrites `/config/.hermes/.env` from the current options and `SUPERVISOR_TOKEN`.
4. Creates `/config/.hermes/config.yaml` only if it does not already exist.
5. Clones Hermes Agent into `/config/.hermes/hermes-agent` when missing.
6. Creates or reuses the Python virtual environment.
7. Installs Hermes Agent with the base editable install plus the Telegram adapter dependency.
8. Executes `hermes gateway run`.

The `.env` file is intentionally regenerated every start so Home Assistant option changes take effect. The Hermes `config.yaml` file is intentionally first-run only so manual user edits are preserved.

## First-Run Hermes Config

```yaml
model:
  provider: ollama-cloud
  model: hermes3:latest
platforms:
  homeassistant:
    enabled: true
  telegram:
    enabled: true
```

The generated model value follows the `ollama_model` add-on option.

## Generated Environment

```env
OLLAMA_API_KEY=<from add-on config>
HASS_TOKEN=<SUPERVISOR_TOKEN>
HASS_URL=http://supervisor/core
TELEGRAM_BOT_TOKEN=<from add-on config, when set>
API_SERVER_KEY=<access_password, when set>
```

## Persistence

All Hermes data lives under `/config/.hermes` and survives add-on restarts and updates:

```text
/config/.hermes/
|-- hermes-agent/      # Hermes source clone and venv
|-- memories/          # Long-term memory
|-- sessions/          # Conversation state
|-- skills/            # Hermes skills
|-- .env               # Regenerated on every start
|-- config.yaml        # Created only on first run
`-- state.db           # Hermes state database
```

## What Is Not Included

This slim add-on intentionally does not include:

- nginx or Home Assistant ingress UI
- ttyd or tmux web terminals
- Chromium, Playwright, or agent-browser
- WhatsApp/Puppeteer bridge
- Homebrew or Go toolchain
- bundled editor and diagnostic tools such as `vim`, `nano`, `htop`, `gh`, `bat`, `fd-find`, ImageMagick, or Ghostscript

Hermes is installed without the `[all]` extra. Telegram support is added through the narrow `python-telegram-bot[webhooks]` dependency only.

## Troubleshooting

If Hermes does not start, check the add-on log first. Common causes are a missing Ollama Cloud API key, an invalid Telegram bot token, or upstream Hermes dependency changes during install.

To force a clean Hermes reinstall, stop the add-on and remove `/config/.hermes/hermes-agent`. Keep `/config/.hermes/config.yaml` if you want to preserve manual Hermes configuration edits.
