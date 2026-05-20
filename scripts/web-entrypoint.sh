#!/bin/bash

set -euo pipefail

# Print commands for debugging
set -x

export ALLOW_CORS="${ALLOW_CORS:-enabled}"

# 1. Clean up potential stale Apache lock/PID files (important when containers restart)
rm -f /var/run/apache2/apache2.pid

# 2. Configure CORS in Apache environment variables
if [ "$ALLOW_CORS" == "enabled" ] || [ "$ALLOW_CORS" == "1" ]; then
    echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
fi

# 3. Ensure both renderd (under _renderd user) and Apache (under www-data user)
# can read/write to the shared socket and tile directories
mkdir -p /run/renderd/ /var/cache/renderd/tiles/
chmod -R 777 /run/renderd/ /var/cache/renderd/tiles/

# 4. Start Apache in the foreground
echo "INFO: Starting Apache HTTP server..."
exec apache2ctl -D FOREGROUND
