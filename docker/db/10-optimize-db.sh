#!/bin/bash
set -euo pipefail

echo "INFO: Applying custom PostgreSQL performance tuning..."
cat /etc/postgresql/postgresql.custom.conf.tmpl >> "$PGDATA/postgresql.conf"

# Append autovacuum configuration (defaulting to on)
AUTOVACUUM="${AUTOVACUUM:-on}"
echo "autovacuum = $AUTOVACUUM" >> "$PGDATA/postgresql.conf"

# Synchronize _renderd role password with POSTGRES_PASSWORD
RENDERD_PASSWORD="${POSTGRES_PASSWORD:-_renderd}"
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-gis}" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '_renderd') THEN
            CREATE ROLE _renderd WITH LOGIN PASSWORD '${RENDERD_PASSWORD}';
        ELSE
            ALTER ROLE _renderd WITH LOGIN PASSWORD '${RENDERD_PASSWORD}';
        END IF;
    END
    \$\$;
EOSQL

