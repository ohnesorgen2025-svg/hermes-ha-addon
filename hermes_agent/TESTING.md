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
