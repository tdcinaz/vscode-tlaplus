FROM registry.hub.docker.com/pandoc/latex:3-ubuntu AS latex

FROM mcr.microsoft.com/devcontainers/typescript-node:18-bookworm

RUN apt update \
    && export DEBIAN_FRONTEND=noninteractive \
    # For running integration tests in the terminal
    && apt install -y libgtk-3-dev xvfb \
    # For running tlaplus tools in the debug window, and for building
    # tla2tools.jar from source (TLATeX overhaul): JDK (compiler) + Ant.
    && apt install -y openjdk-17-jdk ant \
    && rm -rf /var/lib/apt/lists/*

# Add minimal latex installation for tlaplus tools
COPY --from=latex /opt/texlive /opt/texlive
ENV PATH="${PATH}:/opt/texlive/texdir/bin/default"
