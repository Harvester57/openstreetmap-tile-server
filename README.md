# High-Performance OpenStreetMap Tile Server

A fully-featured, high-performance OpenStreetMap (OSM) PNG tile server package based on the **Ubuntu 24.04 LTS manual tile server guide** from [switch2osm.org](https://switch2osm.org/). 

This project implements a decoupled, modern **microservices architecture** managed via **Docker Compose**, separating concerns into independent, highly optimized containerized services for database persistence, high-speed importing, tile rendering, web serving, and background updates.

---

## Microservices Architecture & Directory Layout

The application is split into five distinct microservices, designed to work together through shared storage and network configuration:

```
├── .env                     # Default environment configuration (uses published GHCR images)
├── .env.local               # Local development environment overrides (uses locally built images)
├── docker-compose.yml       # Orchestrates the microservice stack
├── Makefile                 # Simplifies execution with common developer shortcuts
├── README.md                # System documentation and instructions
├── AGENT.md                 # Agent onboarding and layout description
├── CHANGELOG.md             # Version history and release notes
└── docker/
    ├── db/                  # PostgreSQL 18 + PostGIS 3.6 database service
    ├── import/              # One-time data import environment using osm2pgsql
    ├── renderd/             # Daemon rendering map tiles via Mapnik 3.1
    ├── web/                 # Apache2 web server with mod_tile & Leaflet demo
    └── updater/             # Background Osmosis replication update service
```

### The Services
*   **`db`**: Custom PostgreSQL 18 database with PostGIS 3.6. Specifically pre-configured and performance-tuned for geospatial database operations (optimized WAL, disabled JIT, increased shared buffers).
*   **`import`**: A short-lived, one-time execution container containing `osm2pgsql` (with modern **flex output** support), `osmium-tool`, `node-carto`, `gdal-bin`, and `get-external-data.py` for compiling the CartoCSS stylesheet, downloading OSM PBF and polygon files, importing data, and pulling external shapefiles/coastlines.
*   **`renderd`**: The rendering service running `renderd` and Mapnik 3.1. It compiles CartoCSS stylesheet styles if not already compiled and renders PNG tiles on-demand over a shared Unix socket.
*   **`web`**: Front-facing Apache2 web server compiled with the `mod_tile` module. Serves pre-rendered tiles directly from cache or routes tile-rendering requests to the render daemon. Features a built-in Leaflet v1.9.4 interactive map.
*   **`updater`**: A long-running background replication updater. It polls global or regional replication feeds using `osmosis` (initialized via `pyosmium-get-changes`) and trims changesets using `trim_osc.py` for regional synchronization.

---

## Shared Volume Strategy

To coordinate data between decoupled containers safely and with minimal filesystem overhead, this repository relies on Docker named volumes:

*   `osm-db-data`: Stores the PostgreSQL database cluster files.
*   `osm-import-data`: Shared directory storing flat-node files, replication sequence state files, extracted PBF replication timestamps, and custom boundary polygons (`region.poly`).
*   `osm-style`: Shared stylesheet directory containing openstreetmap-carto assets, shapefiles, and compiled Mapnik XML configurations.
*   `osm-tiles`: Shared tile cache folder storing rendered `.png` tiles.
*   `renderd-socket`: High-speed communication folder holding the `/run/renderd/renderd.sock` Unix socket used by `mod_tile` and the render daemon.

---

## Modernized Fork Enhancements

This repository is a modernized, production-ready fork optimized for speed, reliability, and security:

*   **Ubuntu 24.04 LTS Base**: Every component utilizes Ubuntu 24.04 LTS to leverage the latest system packages, libraries, and security patches.
*   **Database & Geospatial Engine**: Powered by **PostgreSQL 18** and **PostGIS 3.6** with pre-configured templates tuned for high geospatial write throughput.
*   **osm2pgsql Flex Output**: Fully migrated to modern **osm2pgsql flex output** (`-O flex` using `openstreetmap-carto-flex.lua` and **openstreetmap-carto v6.0.0** stylesheet).
*   **Automatic Appending Imports**: The importer automatically detects whether the `gis` database has already been initialized. If found, it skips initial index creation and runs `osm2pgsql` in `--append` mode instead of `--create`, enabling incremental data ingestion.
*   **Standardized Security & Permissions**: Enforces least-privilege execution by running `renderd`, database connections, and the background `updater` loop under a non-privileged `_renderd` system user (UID/GID `1001`), while adding Apache's `www-data` user to the `_renderd` group with shared `775` and setgid (`g+s`) permissions on socket and tile cache volumes.
*   **Postgres Performance Tuning**: Reconfigured database settings (disabling `JIT` to eliminate query plan compilation overhead, raising `shared_buffers` to 2GB, tuning checkpoints, and setting a robust 10GB WAL).
*   **Optimized GitHub Actions CI**: Complete migration to GitHub Actions supporting automated `linux/amd64` builds, end-to-end tile rendering verification, image signing and build provenance attestation (Sigstore Cosign), CycloneDX SBOM generation and vulnerability scanning (Anchore + GitHub Code Scanning), and OpenSSF Scorecard supply-chain audits.

---

## Quickstart Guide Option A: Using the Makefile

The easiest way to orchestrate the stack locally is by utilizing the pre-configured `Makefile` shortcuts. By default, the `Makefile` loads `.env.local` (`ENV_FILE ?= .env.local`) so that local builds use local image tags (`openstreetmap-tile-server-*:latest`). To use the pre-built GHCR images defined in `.env` with `make`, pass `ENV_FILE=.env` (for example, `make ENV_FILE=.env import`).

### 1. Build the Images
Compile all five microservice Docker images locally:
```bash
make build
```

### 2. Import OpenStreetMap Data
Trigger the short-lived importer service. By default, this will download and import the Luxembourg dataset:
```bash
make import
```

### 3. Run the Tile Server
Start the core tile serving infrastructure (database, render daemon, and Apache web server):
```bash
make start
```
*Your tile server will be available at `http://localhost:8080/`. You can view the Leaflet demo map at the root URL and retrieve tiles directly via `http://localhost:8080/tile/{z}/{x}/{y}.png`.*

### 4. Run the Tile Server with Background Updates
Start the serving infrastructure along with background osmosis differential updates:
```bash
make start-with-updates
```

### 5. Stack Management
```bash
# View aggregated real-time container logs
make logs

# View running status of the services
make status

# Stop all microservices (preserving data volumes)
make stop

# Stop services and completely destroy all named volumes
make clean
```

---

## Quickstart Guide Option B: Using Native Docker Compose Commands

For advanced developers or environments where `make` is not available, you can control the stack natively using standard `docker compose` CLI commands. By default, Docker Compose loads `.env` (which pulls pre-built images from `ghcr.io`). If building images locally from source, pass `--env-file .env.local` to your commands.

### 1. Build the Images (Optional if pulling pre-built images from GHCR)
```bash
docker compose --env-file .env.local build
```

### 2. Import OpenStreetMap Data
Start the short-lived importer container. Docker Compose will automatically boot the database service, wait for its healthcheck to pass, and execute the import script:
```bash
# Using published GHCR images (.env):
docker compose run --rm import

# OR using locally built images (.env.local):
docker compose --env-file .env.local run --rm import
```

### 3. Run the Tile Server
Launch the core tile serving services in the background:
```bash
docker compose up -d web
```
*(Docker Compose handles dependencies automatically: starting `web` will start `renderd` and wait for its socket healthcheck, which in turn starts `db` and waits for PostgreSQL to become healthy).*

### 4. Run the Tile Server with Background Updates
Launch all serving services alongside the background updater:
```bash
docker compose up -d web updater
```

### 5. Stack Management
```bash
# View real-time container logs
docker compose logs -f

# Check active service containers
docker compose ps

# Stop all running containers and networks (preserving volumes)
docker compose down

# Stop all services and purge all network settings and named volumes
docker compose down -v
```

---

## Detailed Custom Setup & Importing

### Using a Local OSM PBF (and Polygon) File
If you have a local `.osm.pbf` file (and optionally a `.poly` boundary file) you want to import instead of downloading one:

1. Place your file in the project root directory and name it `region.osm.pbf` (and optionally `region.poly`).
2. Open `docker-compose.yml` and uncomment the local volume mapping(s) under the `import` service:
   ```yaml
   volumes:
     - osm-style:/data/style
     - osm-import-data:/data/database
     - ./region.osm.pbf:/data/region.osm.pbf  # <--- Uncomment this line
     - ./region.poly:/data/region.poly        # <--- Optional: Uncomment if mounting a local .poly file
   ```
3. Run the import command:
   ```bash
   make import
   # OR: docker compose run --rm import
   ```

### Letting the Stack Download Custom Datasets
To let the importer download a custom region automatically, pass the remote URL of the `.osm.pbf` (and optionally the `.poly` boundary file) as inline environment variables or configure them in `.env` / `.env.local`:

```bash
DOWNLOAD_PBF="https://download.geofabrik.de/europe/liechtenstein-latest.osm.pbf" \
DOWNLOAD_POLY="https://download.geofabrik.de/europe/liechtenstein.poly" \
make import
```

> [!TIP]
> If you are importing a custom region, we highly recommend providing a `.poly` boundary file. Without it, the background `updater` service will apply global differential updates, which will corrupt and pollute your regional database.

### Incremental / Appending Imports
The import process is fully incremental. If you have already imported a region and want to add another without wiping the database:
1. Provide the new `.osm.pbf` file (either mounted as `region.osm.pbf` or via `DOWNLOAD_PBF`).
2. Run the import again:
   ```bash
   make import
   ```
The container will auto-detect the existing database table structure (`planet_osm_point`), skip initial index creation, and automatically run `osm2pgsql` in `--append` mode.

---

## Automatic Updating and Tile Expiry

To keep your tiles synchronized with live global OSM data:

1. Import your dataset with a polygon bound file (via `DOWNLOAD_POLY` or by mounting it at `/data/region.poly`). During import, `import.sh` also extracts the PBF's embedded replication timestamp (`header.option.osmosis_replication_timestamp`) via `osmium fileinfo` and saves it to `/data/database/replication_timestamp.txt`.
2. Start the stack with the updater enabled:
   ```bash
   make start-with-updates
   # OR: docker compose up -d web updater
   ```
3. On first startup, if the Osmosis workspace (`/data/database/.osmosis/state.txt`) is not yet initialized, `updater` determines the initial replication sequence using `pyosmium-get-changes` from:
   * The explicit `REPLICATION_TIMESTAMP` environment variable (if set),
   * Otherwise, the PBF replication timestamp saved in `/data/database/replication_timestamp.txt` during import,
   * Otherwise, a fallback timestamp of `1 day ago`.
4. The `updater` container continuously pulls OSM diff changesets at every `MAX_INTERVAL_SECONDS` interval, trims them with `trim_osc.py` if `/data/database/region.poly` is present, applies them to the database with `osm2pgsql -a` (automatically adding `--flat-nodes` if `/data/database/flat_nodes.bin` exists), and runs `render_expired` over `/run/renderd/renderd.sock`.
5. **Operational Safeguards**:
   * **Disk Space Check**: Each update cycle verifies that at least `500 MB` of free space remains on `/data/database` before downloading diffs.
   * **Graceful Pause**: Creating a `/data/database/stop.txt` file inside the `osm-import-data` volume will pause replication updates cleanly without stopping the container.

---

## Using an Alternate Rendering Style

By default, the server sets up the standard **OpenStreetMap Carto v6.0.0** style. You can customize the stylesheet by mounting your own stylesheet assets folder:

1. Mount your custom style folder to `/data/style` (or replace the `osm-style` volume mapping in `docker-compose.yml`).
2. Specify the following environment variables if your style files use custom names:
   *   `NAME_LUA`: Lua flex transform stylesheet script (default: `openstreetmap-carto-flex.lua`, used by `import` and `updater`).
   *   `NAME_MML`: MML stylesheet index (default: `project.mml`, used by `import` and `renderd`).
   *   `NAME_SQL`: SQL index definition script (default: `indexes.sql`, used by `import`).

> [!NOTE]
> The `import` service always updates database connection parameters in `project.mml` and recompiles `/data/style/mapnik.xml`. The `renderd` service only compiles `/data/style/mapnik.xml` on startup if that file does not already exist in `/data/style`. If you modify `project.mml` or `.mss` files after importing without re-running `import`, delete `/data/style/mapnik.xml` before restarting `renderd` so it recompiles the XML.

---

## Docker Image Configurations & Environment Files

This repository supports two main deployment environments: pulling pre-built microservice images from the **GitHub Container Registry (GHCR.io)**, or compiling and running the stack **locally from source**. 

These settings are managed via environment files in the project root:

### 1. Remote Images via GHCR (Production / Default)
By default, the `.env` file in the root of the project is configured to pull official, optimized microservice images hosted on GHCR:
```ini
DB_IMAGE=ghcr.io/harvester57/openstreetmap-tile-server-db:latest
IMPORT_IMAGE=ghcr.io/harvester57/openstreetmap-tile-server-import:latest
RENDERD_IMAGE=ghcr.io/harvester57/openstreetmap-tile-server-renderd:latest
WEB_IMAGE=ghcr.io/harvester57/openstreetmap-tile-server-web:latest
UPDATER_IMAGE=ghcr.io/harvester57/openstreetmap-tile-server-updater:latest
```
To run the server using these published images, simply run standard Compose commands (Docker Compose automatically detects and loads the `.env` file):
```bash
docker compose up -d web
```

### 2. Locally Built Images (Local Development)
For developer workflows, working entirely offline, or building your own custom container optimizations from source, use the `.env.local` file (which is also the default used by the `Makefile`):
```ini
DB_IMAGE=openstreetmap-tile-server-db:latest
IMPORT_IMAGE=openstreetmap-tile-server-import:latest
RENDERD_IMAGE=openstreetmap-tile-server-renderd:latest
WEB_IMAGE=openstreetmap-tile-server-web:latest
UPDATER_IMAGE=openstreetmap-tile-server-updater:latest
```
To build and execute the local stack with Docker Compose directly, instruct it to load `.env.local` using the `--env-file` flag (or use the `Makefile` targets):
```bash
# Build all local images from source
docker compose --env-file .env.local build

# Run the locally built services
docker compose --env-file .env.local up -d web
```

---

## Environment Variables Reference

Configure these settings inside a `.env` or `.env.local` file in the repository root, or supply them inline during execution:

| Variable | Default | Affected Services | Description |
| :--- | :--- | :--- | :--- |
| `DB_IMAGE` | `ghcr.io/harvester57/openstreetmap-tile-server-db:latest` | `db` | Docker image tag for the PostgreSQL database service (local tag in `.env.local`). |
| `IMPORT_IMAGE` | `ghcr.io/harvester57/openstreetmap-tile-server-import:latest` | `import` | Docker image tag for the osm2pgsql data importer service (local tag in `.env.local`). |
| `RENDERD_IMAGE` | `ghcr.io/harvester57/openstreetmap-tile-server-renderd:latest` | `renderd` | Docker image tag for the render daemon service (local tag in `.env.local`). |
| `WEB_IMAGE` | `ghcr.io/harvester57/openstreetmap-tile-server-web:latest` | `web` | Docker image tag for the Apache2 web server service (local tag in `.env.local`). |
| `UPDATER_IMAGE` | `ghcr.io/harvester57/openstreetmap-tile-server-updater:latest` | `updater` | Docker image tag for the Osmosis background updater service (local tag in `.env.local`). |
| `PORT` | `8080` | `web` | Exposed host port for the web server and Leaflet map interface. |
| `THREADS` | `4` | `import`, `renderd`, `updater` | Number of CPU cores allocated for database imports, rendering threads, and updates. |
| `ALLOW_CORS` | `enabled` | `web` | Toggles Cross-Origin Resource Sharing (`enabled`/`1` or `disabled`) on Apache. |
| `FLAT_NODES` | `disabled` | `import` | Set to `enabled` (or `1`) to use flat node files (`flat_nodes.bin`). Crucial for full-planet imports; auto-detected by `updater` if created. |
| `OSM2PGSQL_EXTRA_ARGS` | `-C 2500` | `import`, `updater` | Extra arguments forwarded to `osm2pgsql` (e.g., `-C 8192` to raise memory cache). |
| `PGPASSWORD` | `_renderd` | `db`, `import`, `renderd`, `updater` | Database password synchronized across the `postgres` superuser and `_renderd` rendering role. |
| `AUTOVACUUM` | `on` | `db` | Toggles the PostgreSQL autovacuum daemon (`on` or `off`). |
| `SHM_SIZE` | `1gb` | `db` | Shared memory (`/dev/shm`) allocated to the PostgreSQL database container. |
| `DOWNLOAD_PBF` | *(none)* | `import` | Remote URL to fetch the `.osm.pbf` file from if not mounting a local file (defaults to Luxembourg if no local file is present). |
| `DOWNLOAD_POLY` | *(none)* | `import` | Remote URL to download the region boundary `.poly` file. |
| `WGET_ARGS` | *(none)* | `import` | Custom arguments supplied to `wget` when downloading map resources. |
| `NAME_LUA` | `openstreetmap-carto-flex.lua` | `import`, `updater` | Lua flex transform script inside `/data/style/`. |
| `NAME_MML` | `project.mml` | `import`, `renderd` | CartoCSS MML project filename inside `/data/style/`. |
| `NAME_SQL` | `indexes.sql` | `import` | Custom SQL index definition script inside `/data/style/`. |
| `REPLICATION_URL` | `https://planet.openstreetmap.org/replication/hour/` | `updater` | Target URL of the OpenStreetMap OSM change/replication server. |
| `MAX_INTERVAL_SECONDS` | `3600` | `updater` | Maximum duration in seconds replication files cover in a single update loop (and sleep interval between loops). |
| `REPLICATION_TIMESTAMP` | *(none)* | `updater` | Initial ISO-8601 timestamp for Osmosis replication initialization. If empty, uses the PBF timestamp extracted during import, or defaults to 1 day ago. |
| `EXPIRY_MINZOOM` | `13` | `updater` | Minimum zoom level where expired tiles are marked for expiry. |
| `EXPIRY_TOUCHFROM` | `13` | `updater` | Zoom level from which expired tiles are marked dirty (touched) in cache. |
| `EXPIRY_DELETEFROM` | `19` | `updater` | Zoom level from which expired tiles are physically deleted from disk cache. |
| `EXPIRY_MAXZOOM` | `20` | `updater` | Maximum zoom level for tile expiration tracking. |

---

## Performance Tuning & Tweaking

### Shared Memory Allocations
The `db` service in `docker-compose.yml` automatically configures `shm_size` (defaulting to `1gb` via `SHM_SIZE`), alongside custom shared buffers (`shared_buffers = 2GB`) and WAL buffers inside `postgresql.custom.conf.tmpl`. You can raise `SHM_SIZE` in `.env` or `.env.local` for large workloads.

### Large Database Cache Tuning
When importing datasets larger than 10GB, increase the `osm2pgsql` RAM cache. Set `OSM2PGSQL_EXTRA_ARGS` to assign ~75% of your available memory:
```bash
OSM2PGSQL_EXTRA_ARGS="-C 16384" THREADS=12 make import
```

### Flat Nodes File (For Planet Imports)
If importing the entire planet or large regions where database memory usage might trigger out-of-memory exits, enable the flat nodes file storage system:
```bash
FLAT_NODES=enabled make import
```
*Note: Using `FLAT_NODES` alongside the updater container is only supported for full-planet datasets without a polygon bounding file.*

---

## Database Direct Connections

To connect directly to the database service for troubleshooting, GIS data verification, or manual query execution:

```bash
# Connect using the standard psql utility on the database container
docker compose exec db psql -U _renderd -d gis
```

---

## License

```text
Copyright 2019 Alexander Overvoorde

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
