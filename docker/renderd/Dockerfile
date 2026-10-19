# ==============================================================================
# Helper Stage: Stylesheet Clone & Pruning
# ==============================================================================
FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55 AS compiler-stylesheet
RUN apt-get update && apt-get install -y --no-install-recommends git-core ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /root
RUN git clone --branch v6.0.0 https://github.com/openstreetmap-carto/openstreetmap-carto.git --depth 1
WORKDIR /root/openstreetmap-carto
RUN sed -i 's/^--\s*GRANT SELECT ON carto_pois TO <render user>;/GRANT SELECT ON carto_pois TO _renderd;/' common-values.sql && \
    rm -rf .git

# ==============================================================================
# Main Target: Renderer
# ==============================================================================
FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

LABEL org.opencontainers.image.title="openstreetmap-tile-server-renderd" \
    org.opencontainers.image.description="Mapnik + renderd tile rendering daemon microservice for OpenStreetMap PNG tile server." \
    org.opencontainers.image.url="https://github.com/Harvester57/openstreetmap-tile-server" \
    org.opencontainers.image.source="https://github.com/Harvester57/openstreetmap-tile-server" \
    org.opencontainers.image.documentation="https://github.com/Harvester57/openstreetmap-tile-server/blob/master/README.md" \
    org.opencontainers.image.licenses="Apache-2.0" \
    org.opencontainers.image.authors="Alexander Overvoorde (original image), Florian Stosse (fork)" \
    org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04"

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN (groupadd -g 1001 _renderd 2>/dev/null || true) && \
    (useradd -u 1001 -g 1001 -m -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || usermod -d /home/_renderd -s /bin/bash _renderd)

COPY NotoEmoji-Regular.ttf /usr/share/fonts/
COPY unifont-Medium.ttf /usr/share/fonts/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    renderd \
    node-carto \
    python3 \
    python3-yaml \
    fonts-hanazono \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    sudo \
    fonts-unifont && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY renderd.conf /etc/renderd.conf
RUN sed -i 's/\r$//' /etc/renderd.conf

COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/_renderd/src/openstreetmap-carto-backup

RUN mkdir -p /run/renderd/ /data/style/ /var/cache/renderd/tiles/ /home/_renderd/src/ && \
    chown -R _renderd: /data/ /home/_renderd/src/ /run/renderd /var/cache/renderd/tiles/

COPY renderd-entrypoint.sh /renderd-entrypoint.sh
RUN sed -i 's/\r$//' /renderd-entrypoint.sh && chmod +x /renderd-entrypoint.sh

ENTRYPOINT ["/renderd-entrypoint.sh"]

