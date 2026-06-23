FROM postgis/postgis:18-3.6@sha256:c48eb5172cfb005ee094a522fe69f27f1ee9e184ba649fe068520a597fa30409

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
