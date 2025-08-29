FROM ubuntu:24.04@sha256:7c06e91f61fa88c08cc74f7e1b7c69ae24910d745357e0dfe1d2c0322aaf20f9 AS compiler-common
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
&& apt-get install -y --no-install-recommends \
 ca-certificates gnupg lsb-release locales \
 wget curl \
 git-core unzip unrar postgresql-common \
&& locale-gen $LANG && update-locale LANG=$LANG \
&& /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -i -v 17\
&& apt-get update && apt-get -y upgrade\
&& apt-get clean \
&& rm -rf /var/lib/apt/lists/*

###########################################################################################################

FROM compiler-common AS compiler-stylesheet

WORKDIR /root
RUN git clone https://github.com/gravitystorm/openstreetmap-carto.git

WORKDIR /root/openstreetmap-carto
RUN git pull --all && \
git switch --detach v5.9.0 && \
rm -rf .git

###########################################################################################################

FROM compiler-common AS compiler-helper-script

WORKDIR /home/renderer/src
RUN git clone https://github.com/zverik/regional

WORKDIR /home/renderer/src/regional
RUN rm -rf .git \
&& chmod u+x trim_osc.py

###########################################################################################################

FROM compiler-common

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/
ENV DEBIAN_FRONTEND=noninteractive
ENV AUTOVACUUM=on
ENV UPDATES=enabled
ENV REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/
ENV MAX_INTERVAL_SECONDS=3600
ENV PG_VERSION 17

RUN ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone

# Get packages
RUN apt-get update \
&& apt-get install -y --no-install-recommends \
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
 npm \
 osm2pgsql \
 osmium-tool \
 osmosis \
 postgresql-$PG_VERSION \
 postgresql-$PG_VERSION-postgis-3 \
 postgresql-$PG_VERSION-postgis-3-scripts \
 postgis \
 python-is-python3 \
 python3-mapnik \
 python3-lxml \
 python3-psycopg2 \
 python3-shapely \
 python3-pip \
 renderd \
 sudo \
 vim \
 pipx \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN adduser --disabled-password --gecos "" renderer

# Get Noto Emoji Regular font, despite it being deprecated by Google
RUN wget https://github.com/googlefonts/noto-emoji/blob/9a5261d871451f9b5183c93483cbd68ed916b1e9/fonts/NotoEmoji-Regular.ttf?raw=true --content-disposition -P /usr/share/fonts/

# For some reason this one is missing in the default packages
RUN wget https://github.com/stamen/terrain-classic/blob/master/fonts/unifont-Medium.ttf?raw=true --content-disposition -P /usr/share/fonts/

# Install python libraries
RUN pip3 install --break-system-packages \
 requests \
 psycopg2 \
 pyyaml \
 colormath \
 numpy

# Install carto for stylesheet
RUN npm install -g carto@1.2.0

# Configure Apache
RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
&& echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf \
&& a2enconf mod_tile && a2enconf mod_headers
COPY apache.conf /etc/apache2/sites-available/000-default.conf
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
&& ln -sf /dev/stderr /var/log/apache2/error.log

# leaflet
COPY leaflet-demo.html /var/www/html/index.html
WORKDIR /var/www/html/
RUN wget https://github.com/Leaflet/Leaflet/releases/download/v1.9.4/leaflet.zip \
&& unzip leaflet.zip \
&& mv dist/* . \
&& rmdir dist \
&& rm leaflet.zip

# Icon
RUN wget -O /var/www/html/favicon.ico https://www.openstreetmap.org/favicon.ico

# Copy update scripts
COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh \
&& mkdir /var/log/tiles \
&& chmod a+rw /var/log/tiles \
&& ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
&& echo "* * * * *   renderer    openstreetmap-tiles-update-expire.sh\n" >> /etc/crontab

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
&& chown postgres:postgres /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl \
&& echo "host all all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf \
&& echo "host all all ::/0 scram-sha-256" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf

# Create volume directories
RUN mkdir -p /run/renderd/ \
  &&  mkdir  -p  /data/database/  \
  &&  mkdir  -p  /data/style/  \
  &&  mkdir  -p  /home/renderer/src/  \
  &&  chown  -R  renderer:  /data/  \
  &&  chown  -R  renderer:  /home/renderer/src/  \
  &&  chown  -R  renderer:  /run/renderd  \
  &&  mv  /var/lib/postgresql/$PG_VERSION/main/  /data/database/postgres/  \
  &&  mv  /var/cache/renderd/tiles/            /data/tiles/     \
  &&  chown  -R  renderer: /data/tiles \
  &&  ln  -s  /data/database/postgres  /var/lib/postgresql/$PG_VERSION/main             \
  &&  ln  -s  /data/style              /home/renderer/src/openstreetmap-carto  \
  &&  ln  -s  /data/tiles              /var/cache/renderd/tiles                \
;

COPY renderd.conf /etc/renderd.conf

# Install helper script
COPY --from=compiler-helper-script /home/renderer/src/regional /home/renderer/src/regional
COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/renderer/src/openstreetmap-carto-backup

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80 5432
