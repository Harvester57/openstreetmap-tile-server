FROM postgis/postgis:18-3.6@sha256:9ee5e07e7600b079f4c1f7f4cf087f34df3a767f4738d9a38d8b90aecebdf5c1

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
