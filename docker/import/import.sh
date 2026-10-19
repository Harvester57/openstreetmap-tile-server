#!/bin/bash

set -euo pipefail

# Print commands for debugging
set -x

export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-_renderd}"
export PGPASSWORD="${PGPASSWORD:-_renderd}"
export PGDB="${PGDB:-gis}"

# Wait for the database to be healthy and fully accepting connections
echo "INFO: Waiting for database to be ready and accepting connections..."
DB_READY=0
for i in {1..30}; do
    if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB"; then
        echo "INFO: Database is ready."
        DB_READY=1
        break
    fi
    echo "Database not ready yet, sleeping 2s..."
    sleep 2
done

if [ "$DB_READY" -ne 1 ]; then
    echo "ERROR: Database did not become ready within 60 seconds." >&2
    exit 1
fi

# 1. Initialize stylesheet in the shared volume if empty
if [ ! "$(ls -A /data/style/)" ]; then
    echo "INFO: Shared style volume is empty. Copying default style backup..."
    cp -r /home/_renderd/src/openstreetmap-carto-backup/* /data/style/
fi

# 2. Configure remote database connection in project.mml
echo "INFO: Configuring remote database parameters in project.mml..."
python3 -c "
import yaml
import os

mml_path = '/data/style/${NAME_MML:-project.mml}'
if os.path.exists(mml_path):
    with open(mml_path, 'r') as f:
        data = yaml.safe_load(f)
    
    def update_postgis(obj):
        if isinstance(obj, dict):
            if obj.get('type') == 'postgis':
                obj['host'] = os.environ.get('PGHOST', 'db')
                obj['port'] = os.environ.get('PGPORT', '5432')
                obj['user'] = os.environ.get('RENDERD_PGUSER', '_renderd')
                obj['password'] = os.environ.get('PGPASSWORD', '_renderd')
            for k, v in obj.items():
                update_postgis(v)
        elif isinstance(obj, list):
            for item in obj:
                update_postgis(item)
                
    update_postgis(data)
    with open(mml_path, 'w') as f:
        yaml.safe_dump(data, f, default_flow_style=False)
    print('INFO: project.mml database settings updated successfully.')
else:
    print('WARNING: project.mml not found at', mml_path)
"

# 3. Compile CartoCSS to Mapnik XML
echo "INFO: Compiling stylesheet to mapnik.xml..."
cd /data/style/
carto "${NAME_MML:-project.mml}" > mapnik.xml

# 4. Handle sample PBF download or specified download URL
if [ ! -f /data/region.osm.pbf ] && [ -z "${DOWNLOAD_PBF:-}" ]; then
    echo "WARNING: No import file at /data/region.osm.pbf, so downloading Luxembourg as default sample..."
    DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
    DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
fi

if [ -n "${DOWNLOAD_PBF:-}" ]; then
    echo "INFO: Downloading PBF file: $DOWNLOAD_PBF"
    wget ${WGET_ARGS:-} "$DOWNLOAD_PBF" -O /data/region.osm.pbf
    if [ -n "${DOWNLOAD_POLY:-}" ]; then
        echo "INFO: Downloading PBF-POLY file: $DOWNLOAD_POLY"
        wget ${WGET_ARGS:-} "$DOWNLOAD_POLY" -O /data/region.poly
    fi
fi

# 5. Copy region polygon if available and extract PBF replication timestamp for updater
if [ -f /data/region.poly ]; then
    cp /data/region.poly /data/database/region.poly
fi

PBF_TIMESTAMP="$(osmium fileinfo -g header.option.osmosis_replication_timestamp /data/region.osm.pbf || true)"
if [ -n "$PBF_TIMESTAMP" ]; then
    echo "INFO: Extracted PBF replication timestamp: $PBF_TIMESTAMP"
    echo "$PBF_TIMESTAMP" > /data/database/replication_timestamp.txt
fi

# 6. Check if we are appending or doing a fresh import
INITIALIZE="0"
if [ "$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -XtAc "SELECT 1 FROM pg_tables WHERE tablename='planet_osm_point';")" = "1" ]; then
    echo "INFO: Existing planet_osm_point table found. Setting to append mode."
    INITIALIZE="1"
fi

# 7. Configure flat-nodes if enabled
EXTRA_ARGS="${OSM2PGSQL_EXTRA_ARGS:-}"
if [ "${FLAT_NODES:-}" == "enabled" ] || [ "${FLAT_NODES:-}" == "1" ]; then
    EXTRA_ARGS="$EXTRA_ARGS --flat-nodes /data/database/flat_nodes.bin"
fi

# 8. Execute osm2pgsql import
echo "INFO: Starting osm2pgsql data import..."
osm2pgsql -O flex -d "$PGDB" --slim \
  $( (( INITIALIZE == 1 )) && echo '--append' || echo '--create' ) \
  -S "/data/style/${NAME_LUA:-openstreetmap-carto-flex.lua}" \
  --number-processes "${THREADS:-4}" \
  /data/region.osm.pbf \
  $EXTRA_ARGS

# 9. Run custom and standard indexes & functions
if [ "$INITIALIZE" -eq 0 ] && [ -f "/data/style/${NAME_SQL:-indexes.sql}" ]; then
    echo "INFO: Running custom indexes script..."
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -f "/data/style/${NAME_SQL:-indexes.sql}"
fi

if [ -f /data/style/functions.sql ]; then
    echo "INFO: Loading functions.sql..."
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -f /data/style/functions.sql
fi

if [ -f /data/style/common-values.sql ]; then
    echo "INFO: Loading common-values.sql..."
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -f /data/style/common-values.sql
fi

# 10. Download external data (shapefiles, coastlines) on initial import or if missing
if [ -f /data/style/scripts/get-external-data.py ] && [ -f /data/style/external-data.yml ]; then
    if [ "$INITIALIZE" -eq 0 ] || [ ! -d /data/style/data ] || [ -z "$(ls -A /data/style/data 2>/dev/null)" ]; then
        echo "INFO: Running get-external-data.py to pull coastlines & boundaries..."
        python3 /data/style/scripts/get-external-data.py -c /data/style/external-data.yml -D /data/style/data
    else
        echo "INFO: External data already present in /data/style/data, skipping download."
    fi
fi

# 11. Signal that import is complete and ensure non-privileged user ownership
touch /data/database/planet-import-complete
chown -R _renderd:_renderd /data/style /data/database
echo "INFO: Import completed successfully!"

