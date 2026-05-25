FROM postgis/postgis:18-3.6@sha256:750ce289885691e80cae5850a719603345306acba5f9682e15fec09292e62de7

COPY init-db.sql /docker-entrypoint-initdb.d/init-db.sql
COPY 10-optimize-db.sh /docker-entrypoint-initdb.d/10-optimize-db.sh
COPY postgresql.custom.conf.tmpl /etc/postgresql/postgresql.custom.conf.tmpl
