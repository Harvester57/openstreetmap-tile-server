FROM postgis/postgis:18-3.6@sha256:c893f6f2652d11e13f50f8623045b3523991b41d038b4d213dc040f42641f0d7

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
