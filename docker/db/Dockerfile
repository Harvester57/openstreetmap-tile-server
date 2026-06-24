FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PGDATA=/var/lib/postgresql/data

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates locales wget curl sudo \
    postgresql \
    postgresql-contrib \
    postgresql-postgis && \
    locale-gen $LANG && update-locale LANG=$LANG && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /docker-entrypoint-initdb.d && \
    mkdir -p /var/run/postgresql && \
    chown postgres:postgres /var/run/postgresql && \
    chmod 2775 /var/run/postgresql

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

EXPOSE 5432

ENTRYPOINT ["/docker-entrypoint.sh"]
