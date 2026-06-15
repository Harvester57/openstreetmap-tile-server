FROM postgis/postgis:18-3.6@sha256:0d513af346b21c76bf084e90c0589043c30ff379025d079ce4befa9c3a539f72

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
