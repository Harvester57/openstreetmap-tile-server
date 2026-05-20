# ==============================================================================
# Helper Stage: PostgreSQL DB Client Base (ONLY for Importer and Updater)
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS base-db-client

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PG_VERSION=18

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install common utilities, configure locales, and register PostgreSQL client APT repositories
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates gnupg lsb-release locales wget curl unzip bzip2 git-core postgresql-common gnupg2 sudo && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -i -v $PG_VERSION && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup rendering system user '_renderd'
RUN usermod -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || useradd -m -d /home/_renderd -s /bin/bash _renderd


# ==============================================================================
# Helper Stage: Stylesheet Clone & Pruning (Directly from clean Ubuntu)
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS compiler-stylesheet
RUN apt-get update && apt-get install -y --no-install-recommends git-core ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /root
RUN git clone --branch v6.0.0 https://github.com/openstreetmap-carto/openstreetmap-carto.git --depth 1
WORKDIR /root/openstreetmap-carto
RUN sed -i 's/^--\s*GRANT SELECT ON carto_pois TO <render user>;/GRANT SELECT ON carto_pois TO _renderd;/' common-values.sql && \
    rm -rf .git


# ==============================================================================
# Helper Stage: Regional trim script Clone & Pruning (Directly from clean Ubuntu)
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS compiler-helper-script
RUN apt-get update && apt-get install -y --no-install-recommends git-core ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /home/_renderd/src
RUN git clone https://github.com/zverik/regional --depth 1
WORKDIR /home/_renderd/src/regional
RUN rm -rf .git && chmod u+x trim_osc.py


# ==============================================================================
# 1. IMPORTER MICROSERVICE TARGET
# ==============================================================================
FROM base-db-client AS importer

# Install ONLY packages required for style compilation and DB import
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
    liblua5.3-dev \
    lua5.3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy import script and make executable
COPY scripts/import.sh /import.sh
RUN chmod +x /import.sh

# Copy updater script as it's needed for replication metadata initialization
COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh && \
    mkdir -p /var/log/tiles && \
    chmod a+rw /var/log/tiles && \
    ln -sf /home/_renderd/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag

# Preload carto stylesheets from compiler stage
COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/_renderd/src/openstreetmap-carto-backup

# Setup standard volume directories
RUN mkdir -p /data/database/ /data/style/ && \
    chown -R _renderd: /data/

ENTRYPOINT ["/import.sh"]


# ==============================================================================
# 2. RENDERER MICROSERVICE TARGET (No PG Repositories or DB CLI Packages!)
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS renderer

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Configure locales and essential libraries
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates locales wget unzip && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup rendering system user '_renderd'
RUN usermod -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || useradd -m -d /home/_renderd -s /bin/bash _renderd

# Copy common typography fallback fonts to base
COPY NotoEmoji-Regular.ttf /usr/share/fonts/
COPY unifont-Medium.ttf /usr/share/fonts/

# Install ONLY rendering components, Mapnik libraries, and full GIS fonts
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    renderd \
    python-is-python3 \
    python3-mapnik \
    mapnik-utils \
    node-carto \
    gdal-bin \
    fonts-hanazono \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    fonts-unifont \
    sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY renderd.conf /etc/renderd.conf

# Preload carto stylesheets
COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/_renderd/src/openstreetmap-carto-backup

# Setup directories for style configurations, sockets, and tiles
RUN mkdir -p /run/renderd/ /data/style/ /var/cache/renderd/tiles/ /home/_renderd/src/ && \
    chown -R _renderd: /data/ /home/_renderd/src/ /run/renderd /var/cache/renderd/tiles/

COPY scripts/renderd-entrypoint.sh /renderd-entrypoint.sh
RUN chmod +x /renderd-entrypoint.sh

ENTRYPOINT ["/renderd-entrypoint.sh"]


# ==============================================================================
# 3. WEB SERVER MICROSERVICE TARGET (Strictly isolated, no PG Client or Mapnik!)
# ==============================================================================
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS webserver

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Configure locales and base packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates locales wget unzip && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup rendering system user '_renderd' for permissions
RUN usermod -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || useradd -m -d /home/_renderd -s /bin/bash _renderd

# Install ONLY Apache web server and the mod_tile Apache modules (part of renderd pkg)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apache2 \
    renderd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure Apache Modules
RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf && \
    echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf && \
    a2enconf mod_tile && a2enconf mod_headers

COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY renderd.conf /etc/renderd.conf

RUN ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log

# Configure Leaflet map frontend
COPY leaflet-demo.html /var/www/html/index.html
WORKDIR /var/www/html/
RUN wget https://github.com/Leaflet/Leaflet/releases/download/v1.9.4/leaflet.zip && \
    unzip leaflet.zip && \
    mv dist/* . && \
    rmdir dist && \
    rm leaflet.zip

# Get the OpenStreetMap favicon
RUN wget -O /var/www/html/favicon.ico https://www.openstreetmap.org/favicon.ico

# Setup paths for communication with the renderer service
RUN mkdir -p /run/renderd/ /var/cache/renderd/tiles/ && \
    chown -R _renderd: /run/renderd /var/cache/renderd/tiles/

COPY scripts/web-entrypoint.sh /web-entrypoint.sh
RUN chmod +x /web-entrypoint.sh

ENTRYPOINT ["/web-entrypoint.sh"]
EXPOSE 80


# ==============================================================================
# 4. UPDATER MICROSERVICE TARGET
# ==============================================================================
FROM base-db-client AS updater

# Install ONLY incremental diff tools and replication CLI scripts
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
    dateutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy update scripts
COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh && \
    ln -sf /home/_renderd/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag

# Copy helper scripts
COPY --from=compiler-helper-script /home/_renderd/src/regional /home/_renderd/src/regional

# Setup storage and log directories
RUN mkdir -p /var/log/tiles /data/database /var/cache/renderd/tiles && \
    chown -R _renderd: /var/log/tiles /data/database /var/cache/renderd/tiles

COPY scripts/updater-entrypoint.sh /updater-entrypoint.sh
RUN chmod +x /updater-entrypoint.sh

ENTRYPOINT ["/updater-entrypoint.sh"]
