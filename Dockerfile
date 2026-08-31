# dococ — opencode runtime image.
#
# Builds a container with opencode installed via the official install script
# (`curl -fsSL https://opencode.ai/install | bash`), so the binary is always the
# latest release. Project folders and opencode state are mounted at run time.
#
#   docker build -t dococ/opencode:<project-hash> --build-arg APT_PACKAGES="cargo golang" .

# Volatile tag so the image tracks the environment it builds in.
FROM ubuntu:24.04

# Build arg for additional apt packages (space-separated)
ARG APT_PACKAGES=""

# Base tooling: curl/tar for the installer, git for coding agents, ca-certificates
# for HTTPS, and node/npm for opencode plugins and MCP servers (e.g. @playwright/mcp).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        tar \
        git \
        nodejs \
        npm \
    && if [ -n "$APT_PACKAGES" ]; then \
        apt-get install -y --no-install-recommends $APT_PACKAGES; \
    fi \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's base image ships a user "ubuntu" created with the first available UID
# (1000 on x86_64). We reuse it, so the container's default user matches the
# common host UID 1000. dococ additionally passes --user $(id -u):$(id -g) at run
# time, so mounted files match the host owner regardless of the image's UID.
#
# Install the latest opencode binary into the ubuntu user's home.
# --no-modify-path: we set PATH explicitly via ENV rather than editing a shell rc.
ENV OPENCODE_USER=ubuntu \
    OPENCODE_HOME=/home/ubuntu \
    PATH="/home/ubuntu/.opencode/bin:${PATH}"

RUN mkdir -p "$OPENCODE_HOME/.opencode" \
    && chown -R "$OPENCODE_USER":"$OPENCODE_USER" "$OPENCODE_HOME" \
    && runuser -u "$OPENCODE_USER" -- bash -c \
        "curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path"

# Convenience workspace mount point referenced by dococ at run time.
RUN mkdir -p /workspace && chown "$OPENCODE_USER":"$OPENCODE_USER" /workspace

# Default to the ubuntu user. dococ overrides this with --user $(id -u):$(id -g)
# so files written into mounted project folders match the host owner.
USER ubuntu
WORKDIR /workspace

# dococ launches opencode interactively via `docker exec`; CMD here is a fallback.
CMD ["opencode"]
