# Agent Onboarding Guide & System Overview

This repository builds the `ghcr.io/harvester57/openstreetmap-tile-server` Docker image, which hosts an OpenStreetMap PNG tile server based on the **Ubuntu 24.04 LTS switch2osm guide**. It runs PostgreSQL, PostGIS, Apache2 (with `mod_tile`), `renderd`, and the `openstreetmap-carto` stylesheet.

---

## Key Components & Technologies
- **OS**: Ubuntu 24.04 LTS (Docker base)
- **Database**: PostgreSQL 18 + PostGIS 3.6 + `osm2pgsql` (for data import)
- **Rendering**: Mapnik 3.0 + `renderd` (multi-threaded PNG rendering daemon)
- **Server**: Apache2 (with `mod_tile` module pointing to `/tile/` and local Unix socket `/run/renderd/renderd.sock`)
- **Stylesheet**: `openstreetmap-carto` (uses CartoCSS, compiled at runtime to `mapnik.xml`)
- **Updates**: `osmosis` + `osmium` + `pyosmium` + `regional/trim_osc.py` for region-limited diff synchronization.

---

## Repository Layout & File Architecture
- `Dockerfile`: Multi-stage build installing GIS libraries, configuring databases, Apache, and rendering paths.
- `run.sh`: Main entrypoint for two principal modes: `import` (DB initialization and OSM PBF loading) and `run` (serving).
- `openstreetmap-tiles-update-expire.sh`: Executed by cron inside the container to poll, trim, and apply minute/hour diffs.
- `docker-compose.yml`: Standard template showing how to run the container using Docker Compose with external database volumes.
- `Makefile`: Commands for building, running tests, pushing images, and stopping containers.
- `apache.conf` & `renderd.conf`: Routing configurations connecting Apache's HTTP mod_tile to `renderd`.
- `postgresql.custom.conf.tmpl`: PostgreSQL performance-tuning parameters applied at startup.

---

## Key Commands for Agent Workflows

### 1. Build and Run Tests locally
```bash
make build
make test
```

### 2. Manual Run / Import Process
```bash
# 1. Build the Docker image locally
docker build -t openstreetmap-tile-server-local .

# 2. Create storage volume
docker volume create osm-data

# 3. Import region (e.g. Luxembourg default) using the local image
docker run --rm \
  -v osm-data:/data/database/ \
  openstreetmap-tile-server-local import

# 4. Serve the tiles locally using the local image
docker run -p 8080:80 \
  -v osm-data:/data/database/ \
  -d openstreetmap-tile-server-local run
```

---

## Environment Variables Summary (Scope & Defaults)
- `UPDATES=enabled|disabled`: Set to enable background osmosis diff updates.
- `THREADS=4`: Parallel workers for database importing and map tile rendering.
- `ALLOW_CORS=enabled`: If set, adds `Access-Control-Allow-Origin: *` to tile responses.
- `FLAT_NODES=enabled`: Uses a flat node file structure (required for full-planet updates).
- `OSM2PGSQL_EXTRA_ARGS="-C 2500"`: Advanced performance argument tailoring to memory limits.
