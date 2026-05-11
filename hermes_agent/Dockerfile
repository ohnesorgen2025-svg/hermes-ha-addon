ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM ${BUILD_FROM}

# ── System packages ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        jq \
        python3 \
        python3-venv \
        ripgrep \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8

# ── uv (Astral) ─────────────────────────────────────────────────────
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
ENV UV_LINK_MODE=copy

# ── Node.js 22 ──────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Addon files ──────────────────────────────────────────────────────
COPY run.sh /
RUN chmod +x /run.sh

# Runtime HOME (build uses /root, runtime uses /config = addon persistent storage)
ENV HOME=/config

CMD ["/run.sh"]
