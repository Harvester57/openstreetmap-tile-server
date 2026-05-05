#!/bin/bash

set -euo pipefail

function createPostgresConfig() {
  cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
}

function setPostgresPassword() {
    sudo -u postgres psql -c "ALTER USER _renderd PASSWORD '${PGPASSWORD:-_renderd}'"
}

if [ "$#" -ne 1 ]; then
    cat >&2 <<EOF
OpenStreetMap Tile Server

Usage: run.sh <command>

Commands:
    import  Set up the database and import /data/region.osm.pbf
    run     Start Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png

Environment variables (import):
    DOWNLOAD_PBF=<url>           Download a PBF file instead of mounting one
    DOWNLOAD_POLY=<url>          Download a polygon file for region-limited updates
    WGET_ARGS=<args>             Extra arguments passed to wget for downloads
    FLAT_NODES=enabled|disabled  Use flat-nodes mode (recommended for planet imports)
    OSM2PGSQL_EXTRA_ARGS=<args>  Extra arguments passed to osm2pgsql (default: -C 2500)

Environment variables (run):
    ALLOW_CORS=enabled           Set the Access-Control-Allow-Origin header on tiles

Environment variables (import & run):
    THREADS=<n>                  Number of threads for importing / rendering (default: 4)
    UPDATES=enabled|disabled     Enable automatic diff updates from OpenStreetMap
    AUTOVACUUM=on|off            PostgreSQL autovacuum setting (default: on)
    PGPASSWORD=<password>        PostgreSQL password for the _renderd user (default: _renderd)

    NAME_LUA=<file>              Lua script for the style (default: openstreetmap-carto-flex.lua)
    NAME_STYLE=<file>            Style file to use (default: openstreetmap-carto.style)
    NAME_MML=<file>              MML file to render to mapnik.xml (default: project.mml)
    NAME_SQL=<file>              SQL file for index creation (default: indexes.sql)

Environment variables (updates):
    REPLICATION_URL=<url>        Replication server URL (default: https://planet.openstreetmap.org/replication/hour/)
    MAX_INTERVAL_SECONDS=<n>     Max replication interval in seconds (default: 3600)
    EXPIRY_MINZOOM=<n>           Minimum zoom level for tile expiry (default: 13)
    EXPIRY_TOUCHFROM=<n>         Zoom level from which tiles are marked as expired (default: 13)
    EXPIRY_DELETEFROM=<n>        Zoom level from which tiles are deleted (default: 19)
    EXPIRY_MAXZOOM=<n>           Maximum zoom level for tile expiry (default: 20)
EOF
    exit 1
fi

set -x

# if there is no custom style mounted, then use osm-carto
if [ ! "$(ls -A /data/style/)" ]; then
    mv /home/_renderd/src/openstreetmap-carto-backup/* /data/style/
fi

# carto build
if [ ! -f /data/style/mapnik.xml ]; then
    cd /data/style/
    carto ${NAME_MML:-project.mml} > mapnik.xml
fi

if [ "$1" == "import" ]; then
    # Ensure that database directory is in right state
    mkdir -p /data/database/postgres/
    chown _renderd: /data/database/
    chown -R postgres: /var/lib/postgresql /data/database/postgres/
    if [ ! -f /data/database/postgres/PG_VERSION ]; then
        sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/pg_ctl -D /data/database/postgres/ initdb -o "--locale C.UTF-8"
    fi

    # Initialize PostgreSQL
    createPostgresConfig
    service postgresql start
    INITIALIZE="$( sudo -u postgres psql -XtAc "SELECT 1 FROM pg_database WHERE datname='gis'" )"
    if [ $INITIALIZE = '1' ]
    then
        echo "Skipping postgres initialization."
    else
        sudo -u postgres createuser _renderd
        sudo -u postgres createdb -E UTF8 -O _renderd gis
        sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
        sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
        sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO _renderd;"
        sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO _renderd;"
        setPostgresPassword
    fi 

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data/region.osm.pbf ] && [ -z "${DOWNLOAD_PBF:-}" ]; then
        echo "WARNING: No import file at /data/region.osm.pbf, so importing Luxembourg as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
    fi

    if [ -n "${DOWNLOAD_PBF:-}" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget ${WGET_ARGS:-} "$DOWNLOAD_PBF" -O /data/region.osm.pbf
        if [ -n "${DOWNLOAD_POLY:-}" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget ${WGET_ARGS:-} "$DOWNLOAD_POLY" -O /data/region.poly
        fi
    fi

    if [ "${UPDATES:-}" == "enabled" ] || [ "${UPDATES:-}" == "1" ]; then
        # determine and set osmosis_replication_timestamp (for consecutive updates)
        REPLICATION_TIMESTAMP=`osmium fileinfo -g header.option.osmosis_replication_timestamp /data/region.osm.pbf`

        # initial setup of osmosis workspace (for consecutive updates)
        sudo -E -u _renderd openstreetmap-tiles-update-expire.sh $REPLICATION_TIMESTAMP
    fi

    # copy polygon file if available
    if [ -f /data/region.poly ]; then
        cp /data/region.poly /data/database/region.poly
        chown _renderd: /data/database/region.poly
    fi

    # flat-nodes
    if [ "${FLAT_NODES:-}" == "enabled" ] || [ "${FLAT_NODES:-}" == "1" ]; then
        OSM2PGSQL_EXTRA_ARGS="${OSM2PGSQL_EXTRA_ARGS:-} --flat-nodes /data/database/flat_nodes.bin"
    fi

    # Import data
    if [ $INITIALIZE = "1" ]
    then
        echo "Postgres already initialized, appending new data... This is slow, have patience!"
    fi

    sudo -u _renderd osm2pgsql -O flex -d gis --slim \
      $( (( INITIALIZE == "1" )) && echo '--append' || echo '--create' ) \
      -S /data/style/${NAME_LUA:-openstreetmap-carto-flex.lua}  \
      --number-processes ${THREADS:-4}  \
      /data/region.osm.pbf  \
      ${OSM2PGSQL_EXTRA_ARGS:-}  \
    ;

    # old flat-nodes dir
    if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ]; then
        mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
        chown _renderd: /data/database/flat_nodes.bin
    fi

    # Create indexes
    if [ -f /data/style/${NAME_SQL:-indexes.sql} ]; then
        sudo -u postgres psql -d gis -f /data/style/${NAME_SQL:-indexes.sql}
    fi

    # Load functions for OSM Carto v5.9.0
    sudo -u postgres psql -d gis -f /data/style/functions.sql

    # Add additional tables for OSM Carto v6.0.0 onwards
    sudo -u postgres psql -d gis -f /data/style/common-values.sql

    #Import external data
    chown -R _renderd: /home/_renderd/src/ /data/style/
    if [ -f /data/style/scripts/get-external-data.py ] && [ -f /data/style/external-data.yml ]; then
        sudo -E -u _renderd python3 /data/style/scripts/get-external-data.py -c /data/style/external-data.yml -D /data/style/data
    fi

    # Register that data has changed for mod_tile caching purposes
    sudo -u _renderd touch /data/database/planet-import-complete

    service postgresql stop

    exit 0
fi

if [ "$1" == "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    # migrate old files
    if [ -f /data/database/PG_VERSION ] && ! [ -d /data/database/postgres/ ]; then
        mkdir /data/database/postgres/
        mv /data/database/* /data/database/postgres/
    fi
    if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ]; then
        mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
    fi
    if [ -f /data/tiles/data.poly ] && ! [ -f /data/database/region.poly ]; then
        mv /data/tiles/data.poly /data/database/region.poly
    fi

    # sync planet-import-complete file
    if [ -f /data/tiles/planet-import-complete ] && ! [ -f /data/database/planet-import-complete ]; then
        cp /data/tiles/planet-import-complete /data/database/planet-import-complete
    fi
    if ! [ -f /data/tiles/planet-import-complete ] && [ -f /data/database/planet-import-complete ]; then
        cp /data/database/planet-import-complete /data/tiles/planet-import-complete
    fi

    # Fix postgres data privileges
    chown -R postgres: /var/lib/postgresql/ /data/database/postgres/

    # Configure Apache CORS
    if [ "${ALLOW_CORS:-}" == "enabled" ] || [ "${ALLOW_CORS:-}" == "1" ]; then
        echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
    fi

    # Initialize PostgreSQL and Apache
    createPostgresConfig
    service postgresql start
    service apache2 restart
    setPostgresPassword

    # Load functions for OSM Carto v5.9.0
    sudo -u postgres psql -d gis -f /data/style/functions.sql

    # Add additional tables for OSM Carto v6.0.0 onwards
    sudo -u postgres psql -d gis -f /data/style/common-values.sql

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

    # start cron job to trigger consecutive updates
    if [ "${UPDATES:-}" == "enabled" ] || [ "${UPDATES:-}" == "1" ]; then
        printenv > /etc/environment
        /etc/init.d/cron start
        sudo -u _renderd touch /var/log/tiles/run.log; tail -f /var/log/tiles/run.log >> /proc/1/fd/1 &
        sudo -u _renderd touch /var/log/tiles/osmosis.log; tail -f /var/log/tiles/osmosis.log >> /proc/1/fd/1 &
        sudo -u _renderd touch /var/log/tiles/expiry.log; tail -f /var/log/tiles/expiry.log >> /proc/1/fd/1 &
        sudo -u _renderd touch /var/log/tiles/osm2pgsql.log; tail -f /var/log/tiles/osm2pgsql.log >> /proc/1/fd/1 &

    fi

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    sudo -u _renderd renderd -f -c /etc/renderd.conf &
    child=$!
    wait "$child"

    service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1
