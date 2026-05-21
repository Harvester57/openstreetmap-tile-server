# ==============================================================================
# Helper Stage: Stylesheet Clone & Pruning
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS compiler-stylesheet
RUN apt-get update && apt-get install -y --no-install-recommends git-core ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /root
RUN git clone --branch v6.0.0 https://github.com/openstreetmap-carto/openstreetmap-carto.git --depth 1
WORKDIR /root/openstreetmap-carto
RUN sed -i 's/^--\s*GRANT SELECT ON carto_pois TO <render user>;/GRANT SELECT ON carto_pois TO _renderd;/' common-values.sql && \
    rm -rf .git

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
# Main Target: Importer
# ==============================================================================
FROM base-db-client

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    osm2pgsql \
    osmium-tool \
    osmosis \
    postgis \
    gdal-bin \
    postgresql-client-$PG_VERSION \
    python-is-python3 \
    python3 \
    python3-requests \
    python3-yaml \
    python3-psycopg2 \
    node-carto \
    libapache2-mod-tile \
    liblua5.3-dev \
    lua5.3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY import.sh /import.sh
RUN sed -i 's/\r$//' /import.sh && chmod +x /import.sh

RUN mkdir -p /var/log/tiles && \
    chmod a+rw /var/log/tiles && \
    ln -sf /usr/share/doc/libapache2-mod-tile/examples/osmosis-db_replag /usr/bin/osmosis-db_replag

COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/_renderd/src/openstreetmap-carto-backup

RUN mkdir -p /data/database/ /data/style/ && \
    chown -R _renderd: /data/

ENTRYPOINT ["/import.sh"]
