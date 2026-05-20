#!/bin/bash

set -euo pipefail

# Print commands for debugging
set -x

export UPDATES="${UPDATES:-disabled}"
export PGHOST="${PGHOST:-db}"
export PGUSER="${PGUSER:-_renderd}"
export PGPASSWORD="${PGPASSWORD:-_renderd}"

# Ensure correct log and database permissions
mkdir -p /var/log/tiles /data/database
chown -R _renderd: /var/log/tiles /data/database /var/cache/renderd/tiles

# If updates are not enabled, sleep indefinitely so the container stays alive but idle
if [ "$UPDATES" != "enabled" ] && [ "$UPDATES" != "1" ]; then
    echo "INFO: Updates are disabled. Sleeping indefinitely..."
    exec sleep infinity
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
    if sudo -u _renderd openstreetmap-tiles-update-expire.sh; then
        echo "INFO: Update execution completed."
    else
        echo "WARNING: Update check returned non-zero code. Possibly no new replication state, will retry."
    fi
    sleep 60
done
