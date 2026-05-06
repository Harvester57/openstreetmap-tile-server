FROM ubuntu:24.10@sha256:cdf755952ed117f6126ff4e65810bf93767d4c38f5c7185b50ec1f1078b464cc AS compiler-common
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
# PostgreSQL database version to install
ENV PG_VERSION=17

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates gnupg lsb-release locales \
    wget curl unzip bzip2 \
    git-core postgresql-common \
    apache2 \
    cron \
    dateutils \
    fonts-hanazono \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    fonts-unifont \
    gnupg2 \
    gdal-bin \
    liblua5.3-dev \
    lua5.3 \
    mapnik-utils \
    node-carto \
    osm2pgsql \
    osmium-tool \
    osmosis \
    postgis \
    python-is-python3 \
    python3-mapnik \
    python3-lxml \
    python3-shapely \
    python3-pip \
    python3-psycopg2 \
    python3-yaml \
    python3-colormath \
    python3-numpy \
    python3-requests \
    renderd \
    sudo && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -i -v $PG_VERSION && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-$PG_VERSION \
    postgresql-$PG_VERSION-postgis-3 \
    postgresql-$PG_VERSION-postgis-3-scripts \
    postgresql-contrib-$PG_VERSION && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

###########################################################################################################

FROM compiler-common AS compiler-stylesheet

WORKDIR /root
RUN git clone --branch v6.0.0 https://github.com/openstreetmap-carto/openstreetmap-carto.git --depth 1

WORKDIR /root/openstreetmap-carto
RUN sed -i 's/^--\s*GRANT SELECT ON carto_pois TO <render user>;/GRANT SELECT ON carto_pois TO _renderd;/' common-values.sql && \
    rm -rf .git

###########################################################################################################

FROM compiler-common AS compiler-helper-script

WORKDIR /home/_renderd/src
RUN git clone https://github.com/zverik/regional --depth 1

WORKDIR /home/_renderd/src/regional
RUN rm -rf .git \
    && chmod u+x trim_osc.py

###########################################################################################################

FROM compiler-common

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-ubuntu-24-04-lts/
ENV AUTOVACUUM=on
ENV UPDATES=disabled
ENV REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/
ENV MAX_INTERVAL_SECONDS=3600
ENV OSM2PGSQL_EXTRA_ARGS="-C 2500"

RUN ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone && \
    usermod -d /home/_renderd -s /bin/bash _renderd && \
    mkdir -p /home/_renderd && \
    chown _renderd: /home/_renderd

# Get Noto Emoji Regular font, despite it being deprecated by Google
COPY NotoEmoji-Regular.ttf /usr/share/fonts/

# For some reason this one is missing in the default packages
COPY unifont-Medium.ttf /usr/share/fonts/

# Configure Apache
RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf && \
    echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf && \
    a2enconf mod_tile && a2enconf mod_headers

COPY apache.conf /etc/apache2/sites-available/000-default.conf

RUN ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log

# leaflet
COPY leaflet-demo.html /var/www/html/index.html
WORKDIR /var/www/html/
RUN wget https://github.com/Leaflet/Leaflet/releases/download/v1.9.4/leaflet.zip && \
    unzip leaflet.zip && \
    mv dist/* . && \
    rmdir dist && \
    rm leaflet.zip

# Icon
RUN wget -O /var/www/html/favicon.ico https://www.openstreetmap.org/favicon.ico

# Copy update scripts
COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh && \
    mkdir /var/log/tiles && \
    chmod a+rw /var/log/tiles && \
    ln -s /home/_renderd/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag && \
    echo "* * * * *   _renderd    openstreetmap-tiles-update-expire.sh\n" >> /etc/crontab

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/
RUN chown -R postgres:postgres /var/lib/postgresql && \
    chown postgres:postgres /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl && \
    echo "host all all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf && \
    echo "host all all ::/0 scram-sha-256" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf

# Create volume directories
RUN mkdir -p /run/renderd/ /data/database/ /data/style/ /home/_renderd/src/ && \
    chown -R _renderd: /data/ /home/_renderd/src/ /run/renderd && \
    mv /var/lib/postgresql/$PG_VERSION/main/ /data/database/postgres/ && \
    mv /var/cache/renderd/tiles/ /data/tiles/ && \
    chown -R _renderd: /data/tiles && \
    ln -s /data/database/postgres /var/lib/postgresql/$PG_VERSION/main && \
    ln -s /data/style /home/_renderd/src/openstreetmap-carto && \
    ln -s /data/tiles /var/cache/renderd/tiles

COPY renderd.conf /etc/renderd.conf

# Install helper script
COPY --from=compiler-helper-script /home/_renderd/src/regional /home/_renderd/src/regional
COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/_renderd/src/openstreetmap-carto-backup

# Start running
COPY run.sh /
HEALTHCHECK CMD curl --fail http://localhost/ || exit 1
ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80 5432
