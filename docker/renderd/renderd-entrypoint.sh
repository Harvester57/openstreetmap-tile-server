#!/bin/bash

set -euo pipefail

# Print commands for debugging
set -x

# Set umask so that newly created files/directories have group-write permissions
umask 0002

export THREADS="${THREADS:-4}"
export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-_renderd}"
export PGPASSWORD="${PGPASSWORD:-_renderd}"

# 1. Initialize stylesheet in the shared volume if empty
if [ ! "$(ls -A /data/style/)" ]; then
    echo "INFO: Shared style volume is empty. Copying default style backup..."
    cp -r /home/_renderd/src/openstreetmap-carto-backup/* /data/style/
fi

# 2. Compile mapnik.xml if missing
if [ ! -f /data/style/mapnik.xml ]; then
    echo "INFO: mapnik.xml not found in /data/style. Configuring project.mml and compiling stylesheet..."
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
                obj['user'] = os.environ.get('PGUSER', '_renderd')
                obj['password'] = os.environ.get('PGPASSWORD', '_renderd')
            for k, v in obj.items():
                update_postgis(v)
        elif isinstance(obj, list):
            for item in obj:
                update_postgis(item)

    update_postgis(data)
    with open(mml_path, 'w') as f:
        yaml.safe_dump(data, f, default_flow_style=False)
"
    (cd /data/style/ && carto "${NAME_MML:-project.mml}" > mapnik.xml)
fi

# 3. Ensure style directories are symlinked
if [ ! -e /home/_renderd/src/openstreetmap-carto ]; then
    ln -sf /data/style /home/_renderd/src/openstreetmap-carto
fi

# 4. Configure renderd threads in /etc/renderd.conf
sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS}/g" /etc/renderd.conf

# 5. Ensure permissions are correct on the shared socket and tile paths
mkdir -p /run/renderd/ /var/cache/renderd/tiles/
chown -R _renderd: /run/renderd/ /var/cache/renderd/tiles/ /data/style
chmod -R 775 /run/renderd/ /var/cache/renderd/tiles/
find /run/renderd/ /var/cache/renderd/tiles/ -type d -exec chmod g+s {} +

# 6. Start renderd in the foreground under the _renderd user
echo "INFO: Starting renderd daemon..."
exec sudo -u _renderd renderd -f -c /etc/renderd.conf

