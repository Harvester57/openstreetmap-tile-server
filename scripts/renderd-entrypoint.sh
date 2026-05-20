#!/bin/bash

set -euo pipefail

# Print commands for debugging
set -x

export THREADS="${THREADS:-4}"
export PGHOST="${PGHOST:-db}"
export PGUSER="${PGUSER:-_renderd}"
export PGPASSWORD="${PGPASSWORD:-_renderd}"

# 1. Ensure style directories are symlinked
if [ ! -d /home/_renderd/src/openstreetmap-carto ]; then
    ln -sf /data/style /home/_renderd/src/openstreetmap-carto
fi

# 2. Configure renderd threads in /etc/renderd.conf
sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS}/g" /etc/renderd.conf

# 3. Ensure permissions are correct on the shared socket and tile paths
mkdir -p /run/renderd/ /var/cache/renderd/tiles/
chown -R _renderd: /run/renderd/ /var/cache/renderd/tiles/ /data/style

# 4. Start renderd in the foreground under the _renderd user
echo "INFO: Starting renderd daemon..."
exec sudo -u _renderd renderd -f -c /etc/renderd.conf
