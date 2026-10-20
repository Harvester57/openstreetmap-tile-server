FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac

LABEL org.opencontainers.image.title="openstreetmap-tile-server-web" \
    org.opencontainers.image.description="Apache2 + mod_tile front-end web server microservice for OpenStreetMap PNG tile server." \
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

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates locales wget curl unzip \
    apache2 libapache2-mod-tile && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN usermod -a -G _renderd www-data

RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf && \
    echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf && \
    a2enconf mod_tile && a2enconf mod_headers

COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY renderd.conf /etc/renderd.conf
RUN sed -i 's/\r$//' /etc/apache2/sites-available/000-default.conf /etc/renderd.conf


RUN ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log

COPY leaflet-demo.html /var/www/html/index.html
WORKDIR /var/www/html/
RUN wget https://github.com/Leaflet/Leaflet/releases/download/v1.9.4/leaflet.zip && \
    unzip leaflet.zip && \
    mv dist/* . && \
    rmdir dist && \
    rm leaflet.zip

RUN wget -O /var/www/html/favicon.ico https://www.openstreetmap.org/favicon.ico

RUN mkdir -p /run/renderd/ /var/cache/renderd/tiles/ && \
    chown -R _renderd: /run/renderd /var/cache/renderd/tiles/

COPY web-entrypoint.sh /web-entrypoint.sh
RUN sed -i 's/\r$//' /web-entrypoint.sh && chmod +x /web-entrypoint.sh

ENTRYPOINT ["/web-entrypoint.sh"]
EXPOSE 80
