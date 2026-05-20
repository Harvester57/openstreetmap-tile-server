#!/bin/bash

set -euo pipefail

# Print commands for debugging
set -x

export UPDATES="${UPDATES:-disabled}"
export PGHOST="${PGHOST:-db}"
export PGUSER="${PGUSER:-_renderd}"
export PGPASSWORD="${PGPASSWORD:-_renderd}"
export REPLICATION_URL="${REPLICATION_URL:-https://planet.openstreetmap.org/replication/hour/}"
export MAX_INTERVAL_SECONDS="${MAX_INTERVAL_SECONDS:-3600}"

# Ensure correct log and database permissions
mkdir -p /var/log/tiles /data/database
chown -R _renderd: /var/log/tiles /data/database /var/cache/renderd/tiles

# Automatically initialize osmosis workspace if not present
if [ ! -f /data/database/.osmosis/state.txt ]; then
    echo "INFO: Osmosis workspace not found at /data/database/.osmosis/state.txt. Initializing..."
    INITIAL_TIMESTAMP="${REPLICATION_TIMESTAMP:-}"
    if [ -z "$INITIAL_TIMESTAMP" ]; then
        # Default to 1 day ago in ISO format
        INITIAL_TIMESTAMP=$(date -u -d "1 day ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "INFO: No REPLICATION_TIMESTAMP provided. Defaulting to 1 day ago: $INITIAL_TIMESTAMP"
    else
        echo "INFO: Initializing osmosis workspace with provided timestamp: $INITIAL_TIMESTAMP"
    fi
    
    # Run the initialization as renderd user
    sudo -E -u _renderd openstreetmap-tiles-update-expire.sh "$INITIAL_TIMESTAMP"
fi

echo "INFO: Starting updates daemon..."

# Start tailing the logs to stdout so they are visible in docker logs
touch /var/log/tiles/run.log \
      /var/log/tiles/osmosis.log \
      /var/log/tiles/expiry.log \
      /var/log/tiles/osm2pgsql.log

chown _renderd: /var/log/tiles/*.log

tail -f /var/log/tiles/run.log >> /dev/stdout &
tail -f /var/log/tiles/osmosis.log >> /dev/stdout &
tail -f /var/log/tiles/expiry.log >> /dev/stdout &
tail -f /var/log/tiles/osm2pgsql.log >> /dev/stdout &

# Run replication updater loop in the foreground
while true; do
    echo "INFO: Triggering replication update checks..."
    # Execute the update script as the renderd user
    if sudo -E -u _renderd openstreetmap-tiles-update-expire.sh; then
        echo "INFO: Update execution completed."
    else
        echo "WARNING: Update check returned non-zero code. Possibly no new replication state, will retry."
    fi
    sleep "$MAX_INTERVAL_SECONDS"
done
