FROM postgis/postgis:18-3.6@sha256:60f6ad1d21ea86a67d47780b9a0d1e1d200500f62b19293fa834d0dea80b8677

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

