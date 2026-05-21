#!/bin/bash
set -e

echo "INFO: Applying custom PostgreSQL performance tuning..."
cat /etc/postgresql/postgresql.custom.conf.tmpl >> "$PGDATA/postgresql.conf"

# Append autovacuum configuration (defaulting to on)
AUTOVACUUM="${AUTOVACUUM:-on}"
echo "autovacuum = $AUTOVACUUM" >> "$PGDATA/postgresql.conf"
