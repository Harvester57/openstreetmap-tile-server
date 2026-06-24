#!/usr/bin/env bash
set -euo pipefail

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
export PGDATA

find_bin() {
    local name="$1"
    if command -v "${name}" >/dev/null 2>&1; then
        command -v "${name}"
        return 0
    fi
    for p in /usr/lib/postgresql/*/bin/"${name}"; do
        [ -x "${p}" ] && { printf '%s' "${p}"; return 0; }
    done
    return 1
}

INITDB_BIN="$(find_bin initdb || true)"
POSTGRES_BIN="$(find_bin postgres || true)"
PSQL_BIN="$(find_bin psql || true)"

if [ -z "$INITDB_BIN" ] || [ -z "$POSTGRES_BIN" ] || [ -z "$PSQL_BIN" ]; then
    echo "Error: could not locate PostgreSQL binaries (initdb/postgres/psql)."
    echo "Searched PATH and /usr/lib/postgresql/*/bin. Please ensure PostgreSQL is installed."
    exit 1
fi

run_init_scripts() {
    if [ -d /docker-entrypoint-initdb.d ]; then
        for f in /docker-entrypoint-initdb.d/*; do
            [ -f "$f" ] || continue
            case "$f" in
                *.sql)
                    echo "Running $f..."
                    sudo -u postgres "$PSQL_BIN" -v ON_ERROR_STOP=1 -d "${POSTGRES_DB:-postgres}" -f "$f"
                    ;;
                *.sh)
                    echo "Running $f..."
                    chmod +x "$f" || true
                    bash "$f"
                    ;;
                *)
                    echo "Ignoring $f"
                    ;;
            esac
        done
    fi
}

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"

    sudo -u postgres "$INITDB_BIN" -D "$PGDATA" --locale=C.UTF-8 --encoding=UTF8

    if ! grep -qE '^host\s+all\s+all\s+0\.0\.0\.0/0' "$PGDATA/pg_hba.conf" 2>/dev/null; then
        echo "host all all 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
        echo "host all all ::/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
        chown postgres:postgres "$PGDATA/pg_hba.conf" || true
    fi

    echo "Starting PostgreSQL for init script execution..."
    sudo -u postgres "$POSTGRES_BIN" -D "$PGDATA" &
    PG_PID=$!

    echo "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if sudo -u postgres "$PSQL_BIN" -c "SELECT 1" >/dev/null 2>&1; then
            echo "PostgreSQL is ready!"
            break
        fi
        echo "Waiting... ($i/30)"
        sleep 1
    done

    if [ -n "${POSTGRES_PASSWORD:-}" ]; then
        echo "Setting postgres password from POSTGRES_PASSWORD..."
        sudo -u postgres "$PSQL_BIN" -v ON_ERROR_STOP=1 -d postgres -c "ALTER USER \"${POSTGRES_USER:-postgres}\" PASSWORD '${POSTGRES_PASSWORD}';"
    else
        echo "Warning: POSTGRES_PASSWORD is not set; postgres password will not be configured."
    fi

    if [ -n "${POSTGRES_DB:-}" ]; then
        echo "Ensuring database '${POSTGRES_DB}' exists..."
        if ! sudo -u postgres "$PSQL_BIN" -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" postgres | grep -q 1; then
            sudo -u postgres "$PSQL_BIN" -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_USER:-postgres}\";"
        fi
    fi

    run_init_scripts

    echo "Stopping PostgreSQL after init scripts..."
    kill "$PG_PID"
    wait "$PG_PID" || true
fi

exec sudo -u postgres "$POSTGRES_BIN" -D "$PGDATA"
