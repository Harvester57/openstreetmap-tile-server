FROM postgis/postgis:18-3.6@sha256:4a43e3c3e5d55b9208240fc71db543b79c638766280c625a425bd0a2390989c4

LABEL org.opencontainers.image.title="openstreetmap-tile-server-db" \
    org.opencontainers.image.description="PostgreSQL 18 + PostGIS 3.6 database microservice for OpenStreetMap PNG tile server." \
    org.opencontainers.image.url="https://github.com/Harvester57/openstreetmap-tile-server" \
    org.opencontainers.image.source="https://github.com/Harvester57/openstreetmap-tile-server" \
    org.opencontainers.image.documentation="https://github.com/Harvester57/openstreetmap-tile-server/blob/master/README.md" \
    org.opencontainers.image.licenses="Apache-2.0" \
    org.opencontainers.image.authors="Alexander Overvoorde (original image), Florian Stosse (fork)" \
    org.opencontainers.image.base.name="docker.io/postgis/postgis:18-3.6"

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl

RUN sed -i 's/\r$//' /docker-entrypoint-initdb.d/init-db.sql \
        /docker-entrypoint-initdb.d/10-optimize-db.sh \
        /etc/postgresql/postgresql.custom.conf.tmpl && \
    chmod +x /docker-entrypoint-initdb.d/10-optimize-db.sh

