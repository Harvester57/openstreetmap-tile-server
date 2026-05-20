# Agent Onboarding Guide & System Overview

This repository builds a suite of Docker images for an OpenStreetMap PNG tile server, based on the **Ubuntu 24.04 LTS switch2osm guide**. The project uses a multi-container microservices architecture orchestrated by **Docker Compose**, separating database, import, rendering, serving, and updating concerns.

---

## Key Components & Technologies
- **OS**: Ubuntu 24.04 LTS (Docker base for all services except `db`)
- **Database (`db`)**: Running PostgreSQL 18 + PostGIS 3.6. Custom performance-tuned and optimized for geospatial workload (JIT disabled, increased shared buffers).
- **Importer (`import`)**: Short-lived service containing `osm2pgsql` (with modern **flex output** support), `osmosis`, and `osmium-tool` for importing OSM PBF files.
- **Rendering (`renderd`)**: Multi-threaded PNG rendering daemon running Mapnik 3.0 + `renderd`. Uses the **openstreetmap-carto v6.0.0** stylesheet compiled dynamically.
- **Server (`web`)**: Front-facing Apache2 web server with `mod_tile` communicating with the renderer over a shared Unix socket (`/run/renderd/renderd.sock`).
- **Updates (`updater`)**: Running background replication updates with `osmosis` and `regional/trim_osc.py` for regional synchronization.

---

## Repository Layout & File Architecture
- `docker-compose.yml`: Main compose file orchestrating all five microservices, mounting shared volumes, and defining environment variables.
- `Makefile`: Utility shortcuts mapping directly to compose commands to build, import, run, and clean the stack.
- `docker/`:
  - `db/`: Custom PostGIS PostgreSQL 18 database files.
    - `Dockerfile`: Extends the official `postgis/postgis:18-3.6` base.
    - `init-db.sql`: Database schema initialization (creation of `gis` database, extensions, roles).
    - `10-optimize-db.sh`: Applies optimized configurations at database initialization.
    - `postgresql.custom.conf.tmpl`: Custom performance-tuning template applied at startup.
  - `import/`: One-time data import environment.
    - `Dockerfile`: Sets up PostgreSQL client and import tools. Clones default stylesheet.
    - `import.sh`: Script downloading OSM PBF data and executing `osm2pgsql` in `--create` or `--append` mode.
  - `renderd/`: Daemon image rendering map tiles.
    - `Dockerfile`: Ubuntu 24.04 base installing renderd, Mapnik, and font dependencies.
    - `renderd-entrypoint.sh`: Compiles Cartesian CSS styling to mapnik XML and runs `renderd`.
    - `renderd.conf`: Renderer configuration pointing to `/run/renderd/renderd.sock` and XML style sheet.
  - `web/`: Front-facing web server.
    - `Dockerfile`: Installs Apache2 with `mod_tile` module and pre-installs a Leaflet-based demo map.
    - `apache.conf`: Routes `/tile/` requests to renderd Unix socket and loads `mod_headers` and `mod_tile`.
    - `web-entrypoint.sh`: Sets up permissions and runs Apache in the foreground.
  - `updater/`: background diff updating service.
    - `Dockerfile`: Clones regional trimming tools (`regional/trim_osc.py`) and installs `osmosis`/`osm2pgsql`.
    - `updater-entrypoint.sh`: Replication update loops fetching regional differential updates.
    - `openstreetmap-tiles-update-expire.sh`: Legacy cron-style script driving diff updates and tile expiry.

---

## Key Commands for Agent Workflows

### 1. Build and Run the Stack locally
Using the project `Makefile`, you can orchestrate the entire pipeline:
```bash
# Build all microservices targets concurrently
make build

# Trigger import pipeline (downloads Luxembourg dataset by default)
make import

# Start the tile serving infrastructure (db, renderd, web)
make start

# Start the tile serving infrastructure along with background updates (db, renderd, web, updater)
make start-with-updates

# View logs from all running microservices
make logs

# Check status of running services
make status

# Stop all microservices
make stop

# Clean up all containers, networks, and named volumes
make clean
```

### 2. Manual Testing & CI Simulation
To run local tests or simulate the GitHub Actions verification pipeline:
```bash
# 1. Build and import
make build
make import

# 2. Start serving
make start

# 3. Fetch a sample tile via curl to verify serving and rendering work
curl --fail http://localhost:8080/tile/0/0/0.png -o 000.png

# 4. Tear down the stack and clean volumes
make clean
```

---

## Environment Variables Summary (Scope & Defaults)
- `THREADS=4`: Parallel workers for database importing and map tile rendering (passed to `import`, `renderd`, and `updater`).
- `ALLOW_CORS=enabled`: If set, adds `Access-Control-Allow-Origin: *` to tile responses (configured in `web` environment).
- `FLAT_NODES=disabled`: Uses a flat node file structure (set to `enabled` for full-planet imports; passed to `import`).
- `OSM2PGSQL_EXTRA_ARGS="-C 2500"`: Tailors cache allocation to system memory limits (passed to `import`).
- `DOWNLOAD_PBF`: URL to download an OSM `.pbf` dataset during import if not mounted locally.
- `PGPASSWORD=_renderd`: PostgreSQL password for the `_renderd` user.

