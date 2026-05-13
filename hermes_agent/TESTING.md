# Test Report

## Phase 3: Slim Build and Gateway Startup

Date: 2026-05-11
Host: macOS with Docker Desktop 29.2.1
Target platform: linux/amd64
Image tag: `hermes-ha-addon-slim:latest`

## Build

Command:

```bash
docker build --no-cache --platform linux/amd64 \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm \
  -t hermes-ha-addon-slim .
```

Result: success.

## Container Startup

Command:

```bash
docker run -d --platform linux/amd64 \
  --name hermes-ha-addon-slim-test \
  -e SUPERVISOR_TOKEN=test \
  -v "$PWD/test-config:/config" \
  -v "$PWD/test-data:/data:ro" \
  hermes-ha-addon-slim
```

Observed startup sequence:

```text
[run] Writing /config/.hermes/.env
[run] Creating first-run Hermes config
[run] Cloning Hermes Agent...
[run] Creating Python environment...
[run] Installing Hermes Agent...
 + hermes-agent==0.13.0 (from file:///config/.hermes/hermes-agent)
 + python-telegram-bot==22.7
[run] Starting Hermes Gateway
```

Container state after startup:

```text
running 0
```

Local Docker caveat: the gateway logs expected platform connection errors because this test container is not running inside the Home Assistant Supervisor network and the test config does not include a real Telegram bot token:

```text
[Homeassistant] Failed to connect: Cannot connect to host supervisor:80
[Telegram] No bot token configured
```

These errors did not terminate the gateway process. They are external test-environment limitations, not image or entrypoint startup failures.

## Image Size

Measured with Docker inspect:

```text
331697017 bytes
```

That is about 316 MiB and is below the 500 MB target.

Docker Desktop also reported this virtual/uncompressed display size:

```text
REPOSITORY             TAG       SIZE
hermes-ha-addon-slim   latest    1.32GB
```

Layer analysis showed the largest remaining layers are runtime dependencies required by the current design: Debian runtime packages, Node.js 22, and uv.

## Fixes Found During Test

- Removed direct bashio sourcing from `run.sh`; local HA base image execution failed with `/usr/lib/bashio/bashio: line 25: 1: script to source must be provided`.
- Added the narrow Telegram runtime dependency `python-telegram-bot[webhooks]>=22.6,<23` instead of using Hermes `[all]` or broad `[messaging]` extras.
- Removed final-image compiler and development packages from the Dockerfile.

## Update Mechanism Test

Date: 2026-05-13
Image tag: `hermes-ha-addon-slim:latest`

Verified behavior:

- Created the fork `ohnesorgen2025-svg/hermes-agent` from `NousResearch/hermes-agent`.
- Built the add-on image with the new `run.sh`.
- Started with an existing `/config/.hermes` test directory containing preserved `config.yaml`, `memories/`, `sessions/`, `skills/`, and `state.db` marker files.
- Confirmed the managed source clone uses `https://github.com/ohnesorgen2025-svg/hermes-agent.git` as `origin`.
- Confirmed an existing clone is refreshed with `git fetch` and `git reset --hard origin/main`.
- Confirmed `.env` is regenerated and includes `TELEGRAM_ALLOWED_USERS` when configured.
- Confirmed existing user data outside `/config/.hermes/hermes-agent` is preserved.
- Confirmed the install marker now includes both the source revision and add-on-managed dependency signature.

Observed update-path startup sequence:

```text
[run] Writing /config/.hermes/.env
[run] Updating Hermes Agent source from https://github.com/ohnesorgen2025-svg/hermes-agent.git (main)...
HEAD is now at 1979ef580 chore(release): map iuyup author for PR #6155 salvage
[run] Installing Hermes Agent...
 + aiohttp==3.13.5
 ~ hermes-agent==0.13.0 (from file:///config/.hermes/hermes-agent)
[run] Starting Hermes Gateway
```

Container state after update-path startup:

```text
running 0
```

Local Docker caveat: Home Assistant and Telegram connection warnings are expected without the Supervisor network and a real Telegram bot token. The gateway process remained running.
