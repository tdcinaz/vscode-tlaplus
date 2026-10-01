FROM registry.hub.docker.com/pandoc/latex:3-ubuntu AS latex

# Node 22 matches CI (.github/workflows/ci.yml) and @types/node.
FROM mcr.microsoft.com/devcontainers/typescript-node:22-bookworm

RUN apt update \
    && export DEBIAN_FRONTEND=noninteractive \
    # For running integration tests in the terminal
    && apt install -y libgtk-3-dev xvfb \
    # For running tlaplus tools in the debug window, and for building
    # tla2tools.jar from source (TLATeX overhaul): JDK 17 (matches upstream
    # tlaplus CI) + Ant with the optional tasks (junit) customBuild.xml needs.
    && apt install -y openjdk-17-jdk ant ant-optional \
    # For inspecting TLATeX output: poppler renders PDF pages to PNG
    # (scripts/tlatex-dev.sh render / pdfdiff; ImageMagick's `compare` ships
    # with the base image) and extracts text. shellcheck lints the dev script.
    && apt install -y poppler-utils shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Add minimal latex installation for tlaplus tools
COPY --from=latex /opt/texlive /opt/texlive
ENV PATH="${PATH}:/opt/texlive/texdir/bin/default"
