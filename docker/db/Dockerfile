FROM postgis/postgis:18-3.6@sha256:804c0a7b287a58e40d7b6ea012d97346922f56a301de9f6c4860ef4c4059f259

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
