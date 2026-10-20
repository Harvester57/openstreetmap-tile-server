# Agent Onboarding Guide & System Overview

This repository builds a suite of Docker images for an OpenStreetMap PNG tile server, based on the **Ubuntu 24.04 LTS switch2osm guide**. The project uses a multi-container microservices architecture orchestrated by **Docker Compose**, separating database, import, rendering, serving, and updating concerns.

---

## Key Components & Technologies
- **OS**: Ubuntu 24.04 LTS (Docker base for all services except `db`)
- **Database (`db`)**: Running PostgreSQL 18 + PostGIS 3.6. Custom performance-tuned and optimized for geospatial workload (JIT disabled, increased shared buffers).
- **Importer (`import`)**: Short-lived service containing `osm2pgsql` (with modern **flex output** support), `osmium-tool`, `node-carto`, `gdal-bin`, and `get-external-data.py` for compiling stylesheets, importing OSM PBF files, and fetching external shapefiles/coastlines.
- **Rendering (`renderd`)**: Multi-threaded PNG rendering daemon running Mapnik 3.1 + `renderd`. Uses the **openstreetmap-carto v6.0.0** stylesheet compiled dynamically if not already present.
- **Server (`web`)**: Front-facing Apache2 web server with `mod_tile` communicating with the renderer over a shared Unix socket (`/run/renderd/renderd.sock`).
- **Updates (`updater`)**: Running background replication updates with `osmosis` (initialized via `pyosmium-get-changes`), `osm2pgsql`, `render_expired`, and `regional/trim_osc.py` for regional synchronization.

---

## Repository Layout & File Architecture
- `.env`: Default environment configuration pointing to published GHCR container images.
- `.env.local`: Local development environment configuration pointing to locally built container images (used by default in `Makefile`).
- `docker-compose.yml`: Main compose file orchestrating all five microservices, mounting shared volumes, and defining environment variables and healthchecks.
- `Makefile`: Utility shortcuts mapping directly to compose commands (`--env-file .env.local` by default) to build, import, run, and clean the stack.
- `README.md`: End-user documentation, setup instructions, and environment variable reference.
- `CHANGELOG.md`: Semantic Versioning release notes and changelog history.
- `.github/`:
  - `dependabot.yml`: Weekly automated dependency updates for all 5 Dockerfiles and GitHub Actions.
  - `workflows/build-and-test.yaml`: CI/CD pipeline building `linux/amd64` images, running end-to-end tile rendering tests, publishing and signing GHCR images with Sigstore Cosign, and scanning CycloneDX SBOMs with Anchore.
  - `workflows/dependency-review.yml`: Pull request dependency vulnerability scanning.
  - `workflows/scorecards.yml`: OpenSSF Scorecard supply-chain security analysis.
- `docker/`:
  - `db/`: Custom PostGIS PostgreSQL 18 database files.
    - `Dockerfile`: Extends the official `postgis/postgis:18-3.6` base.
    - `init-db.sql`: Database schema initialization (creation of `gis` database, `postgis` and `hstore` extensions, `_renderd` role and ownership).
    - `10-optimize-db.sh`: Applies optimized configurations (`postgresql.custom.conf.tmpl`, `autovacuum`) and syncs `_renderd` password with `POSTGRES_PASSWORD` at database initialization.
    - `postgresql.custom.conf.tmpl`: Custom performance-tuning template applied at initialization.
  - `import/`: One-time data import environment.
    - `Dockerfile`: Sets up PostgreSQL 18 client, `osm2pgsql`, `osmium-tool`, `postgis`, `gdal-bin`, `python3` dependencies, and `node-carto`. Clones default `openstreetmap-carto` v6.0.0 stylesheet.
    - `import.sh`: Initializes `/data/style`, updates DB connection settings in `project.mml`, compiles `mapnik.xml`, downloads OSM PBF and `.poly` data, extracts the PBF replication timestamp to `/data/database/replication_timestamp.txt`, executes `osm2pgsql` (connecting as DB user `_renderd`) in `--create` or `--append` mode, loads SQL indexes/functions, pulls external shapefiles via `get-external-data.py`, and sets `_renderd:_renderd` ownership on `/data/style` and `/data/database`.
  - `renderd/`: Daemon image rendering map tiles.
    - `Dockerfile`: Ubuntu 24.04 base installing `renderd`, Mapnik 3.1, `node-carto`, and font dependencies (including bundled `NotoEmoji-Regular.ttf` and `unifont-Medium.ttf`).
    - `renderd-entrypoint.sh`: Initializes `/data/style` and compiles `/data/style/mapnik.xml` if missing, configures `num_threads`, sets `775`/`g+s` permissions on `/run/renderd` and `/var/cache/renderd/tiles`, and runs `renderd` in the foreground as `_renderd`.
    - `renderd.conf`: Renderer configuration pointing to `/run/renderd/renderd.sock`, Mapnik 3.1 input plugins, and XML stylesheet.
    - `NotoEmoji-Regular.ttf` & `unifont-Medium.ttf`: Custom fallback font assets copied to `/usr/share/fonts/`.
  - `web/`: Front-facing web server.
    - `Dockerfile`: Installs Apache2 with `libapache2-mod-tile`, adds `www-data` to the `_renderd` group, and pre-installs Leaflet v1.9.4.
    - `apache.conf`: Routes `/tile/` requests to the `renderd` Unix socket and configures `mod_tile` and optional `ALLOW_CORS` headers.
    - `renderd.conf`: Tile layer configuration loaded by `mod_tile` (`LoadTileConfigFile /etc/renderd.conf`).
    - `leaflet-demo.html`: Interactive Leaflet map served at `/var/www/html/index.html`.
    - `web-entrypoint.sh`: Cleans stale Apache PID files, configures CORS in `/etc/apache2/envvars`, ensures shared `775`/`g+s` permissions on `/run/renderd` and `/var/cache/renderd/tiles`, and runs Apache in the foreground.
  - `updater/`: Background diff updating service.
    - `Dockerfile`: Clones regional trimming tools (`zverik/regional` `trim_osc.py`) and installs `osmosis`, `osmium-tool`, `pyosmium`, `osm2pgsql`, `postgresql-client-18`, `renderd`, and `libapache2-mod-tile`.
    - `updater-entrypoint.sh`: Waits for PostgreSQL, tails `/var/log/tiles/*.log` to stdout, initializes the Osmosis workspace (`/data/database/.osmosis/state.txt`) using `REPLICATION_TIMESTAMP`, `/data/database/replication_timestamp.txt`, or `1 day ago`, and runs a foreground loop executing `openstreetmap-tiles-update-expire.sh` as `_renderd` every `MAX_INTERVAL_SECONDS`.
    - `openstreetmap-tiles-update-expire.sh`: Script driving Osmosis diff fetching, optional `trim_osc.py` polygon trimming, `osm2pgsql --append` diff ingestion, and `render_expired` tile cache expiry.

---

## Key Commands for Agent Workflows

### 1. Build and Run the Stack Locally
Using the project `Makefile` (which defaults to `ENV_FILE=.env.local` so local builds use local image tags rather than GHCR tags in `.env`):
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
To run local tests or simulate the GitHub Actions verification pipeline (`.github/workflows/build-and-test.yaml`):
```bash
# 1. Build and import default Luxembourg dataset
make build
make import

# 2. Start serving infrastructure and updater
make start-with-updates

# 3. Fetch sample tiles via curl to verify serving and rendering work across zoom levels
curl --fail http://localhost:8080/tile/0/0/0.png -o 000.png
curl --fail http://localhost:8080/tile/18/138474/85459.png -o empty.png
curl --fail http://localhost:8080/tile/18/135536/89345.png -o example.png

# 4. Tear down the stack and clean volumes
make clean
```

---

## Environment Variables Summary (Scope & Defaults)
- `DB_IMAGE`, `IMPORT_IMAGE`, `RENDERD_IMAGE`, `WEB_IMAGE`, `UPDATER_IMAGE`: Service container image tags (`ghcr.io/harvester57/...` in `.env`, local `openstreetmap-tile-server-...` in `.env.local`).
- `PORT=8080`: Host port mapped to container port `80` on `web`.
- `THREADS=4`: Parallel workers for database importing, map tile rendering, and updates (passed to `import`, `renderd`, and `updater`).
- `ALLOW_CORS=enabled`: If set to `enabled` or `1`, adds `Access-Control-Allow-Origin: *` to HTTP responses (`web`).
- `FLAT_NODES=disabled`: Uses a flat node file at `/data/database/flat_nodes.bin` when set to `enabled` or `1` (passed to `import`, auto-detected by `updater` if the file exists).
- `OSM2PGSQL_EXTRA_ARGS="-C 2500"`: Tailors `osm2pgsql` cache allocation and extra flags (passed to `import` and `updater`).
- `PGPASSWORD=_renderd`: PostgreSQL password synchronized across `postgres` and `_renderd` users (`db`, `import`, `renderd`, `updater`).
- `AUTOVACUUM=on`: Toggles PostgreSQL `autovacuum` during database initialization (`db`).
- `SHM_SIZE=1gb`: Shared memory (`/dev/shm`) allocation for the `db` container.
- `DOWNLOAD_PBF` / `DOWNLOAD_POLY` / `WGET_ARGS`: Optional remote URLs and `wget` flags for downloading `.osm.pbf` and `.poly` files (`import`).
- `NAME_LUA=openstreetmap-carto-flex.lua` (`import`, `updater`), `NAME_MML=project.mml` (`import`, `renderd`), `NAME_SQL=indexes.sql` (`import`): Custom stylesheet filenames inside `/data/style/`.
- `REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/`: Osmosis replication feed URL (`updater`).
- `MAX_INTERVAL_SECONDS=3600`: Maximum replication interval and sleep duration between update cycles (`updater`).
- `REPLICATION_TIMESTAMP`: Optional ISO-8601 start timestamp for Osmosis initialization; if empty, uses `/data/database/replication_timestamp.txt` extracted from the PBF during import, or falls back to `1 day ago` (`updater`).
- `EXPIRY_MINZOOM=13`, `EXPIRY_TOUCHFROM=13`, `EXPIRY_DELETEFROM=19`, `EXPIRY_MAXZOOM=20`: Zoom-level thresholds passed to `render_expired` (`updater`).


