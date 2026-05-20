# openstreetmap-tile-server

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [Ubuntu 24.04 LTS guide](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-ubuntu-24-04-lts/) from [switch2osm.org](https://switch2osm.org/) and therefore uses the default OpenStreetMap style.

## Functional Changes & Fork Enhancements

This repository is a modernized fork starting from commit `61270b8bffa9694c32442f989e14a9f6cf1d1aa3`. The following major upgrades, performance optimizations, and backend enhancements have been introduced:

*   **Ubuntu 24.04 LTS Base Upgrade**: Upgraded the container operating system to Ubuntu 24.04 LTS to align with the latest switch2osm.org manual tile server guide.
*   **Database & Geospatial Engine Upgrades**:
    *   Upgraded database engine to **PostgreSQL 18** (with PostGIS 3.6).
    *   Upgraded default stylesheet to **OpenStreetMap Carto v6.0.0** (fully integrating auxiliary tables `common-values.sql` and `functions.sql`).
*   **Transition to osm2pgsql Flex Output**: Migrated the data import pipeline from the legacy `-S openstreetmap-carto.style` layout to the modern **osm2pgsql flex output** (`-O flex` using `openstreetmap-carto-flex.lua`), enabling advanced rendering layout customization.
*   **Incremental / Appending Imports**: Enhanced `run.sh` to check if the `gis` database has already been initialized. If so, the container skips full PostgreSQL setup and automatically runs `osm2pgsql` in `--append` mode instead of `--create`, enabling incremental data imports without wiping existing datasets.
*   **Standardized Security & User Permissions**: Replaced the custom `renderer` user and folder permissions with the standard Ubuntu `_renderd` system account across all service runners, scripts, cron jobs, and database access routines.
*   **PostgreSQL Performance Tuning**: Optimized `postgresql.custom.conf.tmpl` to handle large write sequences and heavy rendering loads:
    *   Significantly increased database memory limits (`shared_buffers` to 2GB, `maintenance_work_mem` to 1GB, `work_mem` to 256MB).
    *   Tuned WAL operations (`wal_level = minimal`, `max_wal_size = 10GB`, `synchronous_commit = off`, `checkpoint_timeout = 60min`).
    *   Disabled PostgreSQL JIT (`jit = off`) to eliminate significant compilation overhead on complex geospatial queries.
*   **Cleaned and Robust Configuration**:
    *   Extracted the rendering configuration into a standalone, static `renderd.conf` template.
    *   Consolidated `Dockerfile` layers to improve build caching, copying necessary font assets (`NotoEmoji-Regular.ttf` and `unifont-Medium.ttf`) locally instead of downloading them dynamically during builds.
    *   Added standard container `HEALTHCHECK` monitoring.
*   **Modern GitHub Actions CI/CD**: Replaced Travis CI with GitHub Actions workflows supporting automated multi-architecture (`amd64` / `arm64`) builds on native ARM runners, image provenance attestation (Sigstore Cosign), Software Bill of Materials (SBOM) generation, OpenSSF Scorecards, and deployment to `ghcr.io`.
*   **Frontend Updates**: Upgraded the built-in Leaflet map demo to version **v1.9.4** for a cleaner and more secure default map-viewing experience.

## Setting up the server

First create a Docker volume to hold the PostgreSQL database that will contain the OpenStreetMap data:

    docker volume create osm-data

Next, download an `.osm.pbf` extract from geofabrik.de for the region that you're interested in. You can then start importing it into PostgreSQL by running a container and mounting the file as `/data/region.osm.pbf`. For example:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v osm-data:/data/database/ \
    ghcr.io/harvester57/openstreetmap-tile-server:master \
    import
```

If the container exits without errors, then your data has been successfully imported and you are now ready to run the tile server.

Note that the import process requires an internet connection. The run process does not require an internet connection. If you want to run the openstreetmap-tile server on a computer that is isolated, you must first import on an internet connected computer, export the `osm-data` volume as a tarfile, and then restore the data volume on the target computer system.

Also when running on an isolated system, the default `index.html` from the container will not work, as it requires access to the web for the leaflet packages.

### Automatic updates (optional)

If your import is an extract of the planet and has polygonal bounds associated with it, like those from [geofabrik.de](https://download.geofabrik.de/), then it is possible to set your server up for automatic updates. Make sure to reference both the OSM file and the polygon file during the `import` process to facilitate this, and also include the `UPDATES=enabled` variable:

```
docker run \
    -e UPDATES=enabled \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v /absolute/path/to/luxembourg.poly:/data/region.poly \
    -v osm-data:/data/database/ \
    ghcr.io/harvester57/openstreetmap-tile-server:master \
    import
```

Refer to the section *Automatic updating and tile expiry* to actually enable the updates while running the tile server.

Please note: If you're not importing the whole planet, then the `.poly` file is necessary to limit automatic updates to the relevant region.
Therefore, when you only have a `.osm.pbf` file but not a `.poly` file, you should not enable automatic updates.

### Letting the container download the file

It is also possible to let the container download files for you rather than mounting them in advance by using the `DOWNLOAD_PBF` and `DOWNLOAD_POLY` parameters.

You can pass extra arguments to `wget` (e.g. for proxy or retry settings) using the `WGET_ARGS` environment variable.

```
docker run \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -v osm-data:/data/database/ \
    ghcr.io/harvester57/openstreetmap-tile-server:master \
    import
```

### Using an alternate style

By default the container will use openstreetmap-carto if it is not specified. However, you can modify the style at run-time. Be aware you need the style mounted at `run` AND `import` as the Lua script needs to be run:

```
docker run \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -e NAME_LUA=sample.lua \
    -e NAME_STYLE=test.style \
    -e NAME_MML=project.mml \
    -e NAME_SQL=test.sql \
    -v /home/user/openstreetmap-carto-modified:/data/style/ \
    -v osm-data:/data/database/ \
    ghcr.io/harvester57/openstreetmap-tile-server:master \
    import
```

If you do not define the "NAME_*" variables, the script will default to those found in the openstreetmap-carto style.

Be sure to mount the volume during `run` with the same `-v /home/user/openstreetmap-carto-modified:/data/style/`

If you do not see the expected style upon `run` double check your paths as the style may not have been found at the directory specified. By default, `openstreetmap-carto` will be used if a style cannot be found

**Only openstreetmap-carto and styles like it, eg, ones with one lua script, one style, one mml, one SQL can be used**

## Running the server

Run the server like this:

```
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

Your tiles will now be available at `http://localhost:8080/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will then be available on `http://localhost:8080`. Note that it will initially take quite a bit of time to render the larger tiles for the first time.

### Using Docker Compose

The `docker-compose.yml` file included with this repository shows how the aforementioned command can be used with Docker Compose to run your server.

### Preserving rendered tiles

Tiles that have already been rendered will be stored in `/data/tiles/`. To make sure that this data survives container restarts, you should create another volume for it:

```
docker volume create osm-tiles
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    -v osm-tiles:/data/tiles/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

**If you do this, then make sure to also run the import with the `osm-tiles` volume to make sure that caching works properly across updates!**

### Enabling automatic updating (optional)

Given that you've set up your import as described in the *Automatic updates* section during server setup, you can enable the updating process by setting the `UPDATES` variable while running your server as well:

```
docker run \
    -p 8080:80 \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/minute/ \
    -e MAX_INTERVAL_SECONDS=60 \
    -e UPDATES=enabled \
    -v osm-data:/data/database/ \
    -v osm-tiles:/data/tiles/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

This will enable a background process that automatically downloads changes from the OpenStreetMap server, filters them for the relevant region polygon you specified, updates the database and finally marks the affected tiles for rerendering.

### Tile expiration (optional)

Specify custom tile expiration settings to control which zoom level tiles are marked as expired when an update is performed. Tiles can be marked as expired in the cache (TOUCHFROM), but will still be served
until a new tile has been rendered, or deleted from the cache (DELETEFROM), so nothing will be served until a new tile has been rendered.

The example tile expiration values below are the default values.

```
docker run \
    -p 8080:80 \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/minute/ \
    -e MAX_INTERVAL_SECONDS=60 \
    -e UPDATES=enabled \
    -e EXPIRY_MINZOOM=13 \
    -e EXPIRY_TOUCHFROM=13 \
    -e EXPIRY_DELETEFROM=19 \
    -e EXPIRY_MAXZOOM=20 \
    -v osm-data:/data/database/ \
    -v osm-tiles:/data/tiles/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

### Cross-origin resource sharing

To enable the `Access-Control-Allow-Origin` header to be able to retrieve tiles from other domains, simply set the `ALLOW_CORS` variable to `enabled`:

```
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    -e ALLOW_CORS=enabled \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

### Connecting to Postgres

To connect to the PostgreSQL database inside the container, make sure to expose port 5432:

```
docker run \
    -p 8080:80 \
    -p 5432:5432 \
    -v osm-data:/data/database/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

Use the user `_renderd` and the database `gis` to connect.

```
psql -h localhost -U _renderd gis
```

The default password is `_renderd`, but it can be changed using the `PGPASSWORD` environment variable:

```
docker run \
    -p 8080:80 \
    -p 5432:5432 \
    -e PGPASSWORD=secret \
    -v osm-data:/data/database/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

## Performance tuning and tweaking

Details for update procedure and invoked scripts can be found here [link](https://ircama.github.io/osm-carto-tutorials/updating-data/).

### THREADS

The import and tile serving processes use 4 threads by default, but this number can be changed by setting the `THREADS` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e THREADS=24 \
    -v osm-data:/data/database/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

### CACHE

The import and tile serving processes use 800 MB RAM cache by default, but this number can be changed by option -C. For example:
```
docker run \
    -p 8080:80 \
    -e "OSM2PGSQL_EXTRA_ARGS=-C 4096" \
    -v osm-data:/data/database/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

### AUTOVACUUM

The database use the autovacuum feature by default. This behavior can be changed with `AUTOVACUUM` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e AUTOVACUUM=off \
    -v osm-data:/data/database/ \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```

### FLAT_NODES

If you are planning to import the entire planet or you are running into memory errors then you may want to enable the `--flat-nodes` option for osm2pgsql. You can then use it during the import process as follows:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v osm-data:/data/database/ \
    -e "FLAT_NODES=enabled" \
    ghcr.io/harvester57/openstreetmap-tile-server:master \
    import
```

Warning: enabling `FLAT_NOTES` together with `UPDATES` only works for entire planet imports (without a `.poly` file).  Otherwise this will break the automatic update script. This is because trimming the differential updates to the specific regions currently isn't supported when using flat nodes.

### Benchmarks

You can find an example of the import performance to expect with this image on the [OpenStreetMap wiki](https://wiki.openstreetmap.org/wiki/Osm2pgsql/benchmarks#debian_9_.2F_openstreetmap-tile-server).

## Environment variable reference

The following table summarizes all supported environment variables, their default values, and which command (`import`, `run`, or both) they apply to.

| Variable | Default | Scope | Description |
|---|---|---|---|
| `DOWNLOAD_PBF` | *(none)* | `import` | URL to download a PBF file instead of mounting one |
| `DOWNLOAD_POLY` | *(none)* | `import` | URL to download a polygon file for region-limited updates |
| `WGET_ARGS` | *(none)* | `import` | Extra arguments passed to `wget` for downloads |
| `FLAT_NODES` | `disabled` | `import` | Set to `enabled` to use flat-nodes mode (recommended for planet imports) |
| `OSM2PGSQL_EXTRA_ARGS` | `-C 2500` | `import` | Extra arguments passed to `osm2pgsql` (e.g. `-C 4096` for cache) |
| `ALLOW_CORS` | `disabled` | `run` | Set to `enabled` to add the `Access-Control-Allow-Origin` header |
| `THREADS` | `4` | both | Number of threads for importing and tile rendering |
| `UPDATES` | `disabled` | both | Set to `enabled` to activate automatic diff updates |
| `AUTOVACUUM` | `on` | both | PostgreSQL autovacuum setting (`on` or `off`) |
| `PGPASSWORD` | `_renderd` | both | PostgreSQL password for the `_renderd` user |
| `NAME_LUA` | `openstreetmap-carto-flex.lua` | both | Lua transform script for the style |
| `NAME_STYLE` | `openstreetmap-carto.style` | both | Style file to use |
| `NAME_MML` | `project.mml` | both | MML file to render to `mapnik.xml` |
| `NAME_SQL` | `indexes.sql` | both | SQL file for index creation |
| `REPLICATION_URL` | `https://planet.openstreetmap.org/replication/hour/` | updates | Replication server URL |
| `MAX_INTERVAL_SECONDS` | `3600` | updates | Maximum replication interval in seconds |
| `EXPIRY_MINZOOM` | `13` | updates | Minimum zoom level for tile expiry |
| `EXPIRY_TOUCHFROM` | `13` | updates | Zoom level from which expired tiles are marked |
| `EXPIRY_DELETEFROM` | `19` | updates | Zoom level from which expired tiles are deleted |
| `EXPIRY_MAXZOOM` | `20` | updates | Maximum zoom level for tile expiry |

## Troubleshooting

### ERROR: could not resize shared memory segment / No space left on device

If you encounter such entries in the log, it will mean that the default shared memory limit (64 MB) is too low for the container and it should be raised:
```
renderd[121]: ERROR: failed to render TILE default 2 0-3 0-3
renderd[121]: reason: Postgis Plugin: ERROR: could not resize shared memory segment "/PostgreSQL.790133961" to 12615680 bytes: ### No space left on device
```
To raise it use `--shm-size` parameter. For example:
```
docker run \
    -p 8080:80 \
    -v osm-data:/data/database/ \
    --shm-size="192m" \
    -d ghcr.io/harvester57/openstreetmap-tile-server:master \
    run
```
For too high values you may notice excessive CPU load and memory usage. It might be that you will have to experimentally find the best values for yourself.

### The import process unexpectedly exits

You may be running into problems with memory usage during the import. Have a look at the "Flat nodes" section in this README.

## License

```
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
