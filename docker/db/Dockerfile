FROM postgis/postgis:18-3.6@sha256:52d19e8b5a022824eb2e48a77ca448c1e47ab7081bd2bd9ff09e16b92e20326b

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
