# ==============================================================================
# Helper Stage: Regional trim script Clone & Pruning
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS compiler-helper-script
RUN apt-get update && apt-get install -y --no-install-recommends git-core ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /home/_renderd/src
RUN git clone https://github.com/zverik/regional --depth 1
WORKDIR /home/_renderd/src/regional
RUN rm -rf .git && chmod u+x trim_osc.py

# ==============================================================================
# Helper Stage: PostgreSQL DB Client Base
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS base-db-client

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PG_VERSION=18

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates gnupg lsb-release locales wget curl unzip bzip2 git-core postgresql-common gnupg2 sudo && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -i -v $PG_VERSION && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN (groupadd -g 1001 _renderd 2>/dev/null || true) && \
    (useradd -u 1001 -g 1001 -m -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || usermod -d /home/_renderd -s /bin/bash _renderd)

# ==============================================================================
# Main Target: Updater
# ==============================================================================
FROM base-db-client

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    osmosis \
    osmium-tool \
    osm2pgsql \
    postgresql-client-$PG_VERSION \
    python-is-python3 \
    python3 \
    python3-requests \
    python3-yaml \
    python3-psycopg2 \
    python3-lxml \
    python3-shapely \
    python3-colormath \
    python3-numpy \
    dateutils \
    renderd \
    libapache2-mod-tile && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN sed -i 's/\r$//' /usr/bin/openstreetmap-tiles-update-expire.sh && \
    chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh && \
    ln -sf /usr/share/doc/libapache2-mod-tile/examples/osmosis-db_replag /usr/bin/osmosis-db_replag

COPY --from=compiler-helper-script /home/_renderd/src/regional /home/_renderd/src/regional

RUN mkdir -p /var/log/tiles /data/database /var/cache/renderd/tiles && \
    chown -R _renderd: /var/log/tiles /data/database /var/cache/renderd/tiles

COPY updater-entrypoint.sh /updater-entrypoint.sh
RUN sed -i 's/\r$//' /updater-entrypoint.sh && chmod +x /updater-entrypoint.sh

ENTRYPOINT ["/updater-entrypoint.sh"]
