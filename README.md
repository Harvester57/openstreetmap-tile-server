# High-Performance OpenStreetMap Tile Server

A fully-featured, high-performance OpenStreetMap (OSM) PNG tile server package based on the **Ubuntu 24.04 LTS manual tile server guide** from [switch2osm.org](https://switch2osm.org/). 

This project implements a decoupled, modern **microservices architecture** managed via **Docker Compose**, separating concerns into independent, highly optimized containerized services for database persistence, high-speed importing, tile rendering, web serving, and background updates.

---

## Microservices Architecture & Directory Layout

The application is split into five distinct microservices, designed to work together through shared storage and network configuration:

```
├── docker-compose.yml       # Orchestrates the microservice stack
├── Makefile                 # Simplifies execution with common developer shortcuts
├── README.md                # System documentation and instructions
├── AGENT.md                 # Agent onboarding and layout description
└── docker/
    ├── db/                  # PostgreSQL 18 + PostGIS 3.6 database service
    ├── import/              # One-time data import environment using osm2pgsql
    ├── renderd/             # Daemon rendering map tiles via Mapnik 3.0
    ├── web/                 # Apache2 web server with mod_tile & Leaflet demo
    └── updater/             # Background Osmosis replication update service
```

### The Services
*   **`db`**: Custom PostgreSQL 18 database with PostGIS 3.6. Specifically pre-configured and performance-tuned for geospatial database operations (optimized WAL, disabled JIT, increased shared buffers).
*   **`import`**: A short-lived, one-time execution container containing `osm2pgsql` (with modern **flex output** support), `osmosis`, and `osmium-tool` for downloading and importing OSM PBF and polygon files.
*   **`renderd`**: The rendering service running `renderd` and Mapnik 3.0. It compiles CartoCSS stylesheet styles dynamically and renders PNG tiles on-demand over a shared Unix socket.
*   **`web`**: Front-facing Apache2 web server compiled with the `mod_tile` module. Serves pre-rendered tiles directly from cache or routes tile-rendering requests to the render daemon. Features a built-in Leaflet v1.9.4 interactive map.
*   **`updater`**: A long-running background replication updater. It polls global or regional replication feeds using `osmosis` and trims changesets using `trim_osc.py` for regional synchronization.

---

## Shared Volume Strategy

To coordinate data between decoupled containers safely and with minimal filesystem overhead, this repository relies on Docker named volumes:

*   `osm-db-data`: Stores the PostgreSQL database cluster files.
*   `osm-import-data`: Shared directory storing import metrics, replication sequence state files, and custom boundary polygons (`region.poly`).
*   `osm-style`: Shared stylesheet directory containing openstreetmap-carto assets, shapefiles, and compiled Mapnik XML configurations.
*   `osm-tiles`: Shared tile cache folder storing rendered `.png` tiles.
*   `renderd-socket`: High-speed communication folder holding the `/run/renderd/renderd.sock` Unix socket used by `mod_tile` and the render daemon.

---

## Modernized Fork Enhancements

This repository is a modernized, production-ready fork optimized for speed, reliability, and security:

*   **Ubuntu 24.04 LTS Base**: Every component utilizes Ubuntu 24.04 LTS to leverage the latest system packages, libraries, and security patches.
*   **Database & Geospatial Engine**: Powered by **PostgreSQL 18** and **PostGIS 3.6** with pre-configured templates tuned for high geospatial write throughput.
*   **osm2pgsql Flex Output**: Fully migrated to modern **osm2pgsql flex output** (`-O flex` using `openstreetmap-carto-flex.lua` and **openstreetmap-carto v6.0.0** stylesheet).
*   **Automatic Appending Imports**: The importer automatically detects whether the `gis` database has already been initialized. If found, it skips setup and runs `osm2pgsql` in `--append` mode instead of `--create`, enabling incremental data ingestion.
*   **Standardized Security & Permissions**: Restores strict standard security by mapping Apache, the renderer daemon, database connections, and cron updates to a non-privileged `_renderd` system user.
*   **Postgres Performance Tuning**: Reconfigured database settings (disabling `JIT` to eliminate query plan compilation overhead, raising `shared_buffers` to 2GB, tuning checkpoints, and setting a robust 10GB WAL).
*   **Optimized GitHub Actions CI**: Complete migration to GitHub Actions supporting automated multi-architecture (`amd64` / `arm64`) builds, image provenance attestation (Sigstore Cosign), and Software Bill of Materials (SBOM) generation.

---

## Quickstart Guide Option A: Using the Makefile

The easiest way to orchestrate the stack is by utilizing the simple, pre-configured `Makefile` shortcuts:

### 1. Build the Images
Compile all five microservice Docker images:
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

For advanced developers or environments where `make` is not available, you can control the stack natively using standard `docker compose` CLI commands:

### 1. Build the Images
```bash
docker compose build
```

### 2. Import OpenStreetMap Data
Start the short-lived importer container. Docker Compose will automatically boot the database service, wait for its healthcheck to pass, and execute the import script:
```bash
docker compose run --rm import
```

### 3. Run the Tile Server
Launch the core tile serving services in the background:
```bash
docker compose up -d web
```
*(Docker Compose handles dependencies automatically: up-ing `web` will start `renderd`, which in turn starts `db` and waits for it to become healthy).*

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

### Using a Local OSM PBF File
If you have a local `.osm.pbf` file you want to import instead of downloading one:

1. Place your file in the project root directory and name it `region.osm.pbf`.
2. Open `docker-compose.yml` and uncomment the local volume mapping under the `import` service:
   ```yaml
   volumes:
     - osm-style:/data/style
     - osm-import-data:/data/database
     - ./region.osm.pbf:/data/region.osm.pbf  # <--- Uncomment this line
   ```
3. Run the import command:
   ```bash
   make import
   # OR: docker compose run --rm import
   ```

### Letting the Stack Download Custom Datasets
To let the importer download a custom region automatically, pass the remote URL of the `.osm.pbf` (and optionally the `.poly` boundary file) as inline environment variables or configure them in a local `.env` file:

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
The container will auto-detect the existing database table structure, skip the initial schema setup, and automatically run `osm2pgsql` in `--append` mode.

---

## Automatic Updating and Tile Expiry

To keep your tiles synchronized with live global OSM data:

1. Import your dataset with a polygon bound file (via `DOWNLOAD_POLY` or by mounting it at `/data/region.poly`).
2. Start the stack with the updater enabled:
   ```bash
   make start-with-updates
   # OR: docker compose up -d web updater
   ```
3. The `updater` container will continuously pull OSM diff changesets at the configured interval, apply them to the database, and trigger tile expiration routines so that modified tiles are scheduled for rerendering.

---

## Using an Alternate Rendering Style

By default, the server sets up the standard OpenStreetMap Carto style. You can customize the stylesheet by mounting your own stylesheet assets folder:

1. Mount your custom style folder to the `osm-style` named volume or directory.
2. In the `import` and `renderd` configurations, specify the following environment variables if your style files use custom names:
   *   `NAME_LUA`: Lua transform stylesheet script (default: `openstreetmap-carto-flex.lua`).
   *   `NAME_STYLE`: Legacy style sheet layout (default: `openstreetmap-carto.style`).
   *   `NAME_MML`: MML stylesheet index (default: `project.mml`).
   *   `NAME_SQL`: SQL index definition script (default: `indexes.sql`).

---

## Environment Variables Reference

Configure these settings inside a `.env` file in the repository root or supply them inline during execution:

| Variable | Default | Affected Services | Description |
| :--- | :--- | :--- | :--- |
| `PORT` | `8080` | `web` | Exposed host port for the web server and Leaflet map interface. |
| `THREADS` | `4` | `import`, `renderd`, `updater` | Number of CPU cores allocated for database imports, rendering threads, and updates. |
| `ALLOW_CORS` | `enabled` | `web` | Toggles Cross-Origin Resource Sharing (`enabled` or `disabled`) on Apache. |
| `FLAT_NODES` | `disabled` | `import` | Set to `enabled` to use flat node files (`flat_nodes.bin`). Crucial for full-planet imports. |
| `OSM2PGSQL_EXTRA_ARGS` | `-C 2500` | `import` | Extra arguments forwarded to `osm2pgsql` (e.g., `-C 8192` to raise memory cache). |
| `PGPASSWORD` | `_renderd` | *All Services* | Database password for the internal system rendering user. |
| `AUTOVACUUM` | `on` | `db` | Toggles the PostgreSQL autovacuum daemon (`on` or `off`). |
| `DOWNLOAD_PBF` | *(none)* | `import` | Remote URL to fetch the `.osm.pbf` file from if not mounting a local file. |
| `DOWNLOAD_POLY` | *(none)* | `import` | Remote URL to download the region boundary `.poly` file. |
| `WGET_ARGS` | *(none)* | `import` | Custom arguments supplied to `wget` when downloading map resources. |
| `REPLICATION_URL` | `https://planet.openstreetmap.org/replication/hour/` | `updater` | Target URL of the OpenStreetMap OSM change/replication server. |
| `MAX_INTERVAL_SECONDS` | `3600` | `updater` | Maximum duration replication files cover in a single update loop. |
| `EXPIRY_MINZOOM` | `13` | `updater` | Minimum zoom level where expired tiles are marked for expiry. |
| `EXPIRY_TOUCHFROM` | `13` | `updater` | Zoom level where expired tiles are touched in-cache. |
| `EXPIRY_DELETEFROM` | `19` | `updater` | Zoom level where expired tiles are physically deleted from disk cache. |
| `EXPIRY_MAXZOOM` | `20` | `updater` | Maximum zoom level for tile expiration tracking. |

---

## Performance Tuning & Tweaking

### Shared Memory Allocations
Because PostgreSQL runs in a dedicated service, you no longer need to pass `--shm-size` flags at container execution. Custom shared memory and WAL buffers are automatically optimized inside the performance template `postgresql.custom.conf.tmpl` and managed natively by Docker Compose.

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
*Note: Using `FLAT_NODES` alongside `UPDATES` is only supported for full-planet datasets without a polygon bounding file.*

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
