FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN (groupadd -g 1001 _renderd 2>/dev/null || true) && \
    (useradd -u 1001 -g 1001 -m -d /home/_renderd -s /bin/bash _renderd 2>/dev/null || usermod -d /home/_renderd -s /bin/bash _renderd)

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates locales wget unzip \
    apache2 renderd && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN usermod -a -G _renderd www-data

RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf && \
    echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf && \
    a2enconf mod_tile && a2enconf mod_headers

COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY renderd.conf /etc/renderd.conf

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
