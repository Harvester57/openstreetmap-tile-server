FROM postgis/postgis:18-3.6@sha256:1ac8d723bbf66159010056348cb54f521a8ee4c83d8df7ccec0c103ca004c0b8

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
