FROM postgis/postgis:18-3.6@sha256:db37d16842d4518262e0722c0c4a136f3a54001edba13a4edfdcc9ce97f3a793

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
