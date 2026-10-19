# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [3.1.0] - 2026-10-19

### Added
- **Automatic Replication Start Time**: The importer now reads the replication timestamp embedded in the imported `.osm.pbf` file so the background updater automatically starts syncing from the exact age of your map data, without requiring manual timestamp configuration.
- **Custom Stylesheet Overrides**: Added support for `NAME_LUA`, `NAME_MML`, and `NAME_SQL` environment variables to make it easy to use custom CartoCSS stylesheets and Lua flex scripts.
- **Configurable Database Shared Memory**: Added the `SHM_SIZE` setting (defaulting to `1gb`) so users can easily increase PostgreSQL shared memory for large imports.
- **Service Readiness Checks**: Added healthchecks to the renderer and web server so containers start in the right order and wait until the rendering socket is ready before accepting web traffic.
- **Cross-Platform Line Endings**: Added a `.gitattributes` file to ensure scripts and configuration files always keep Linux-compatible (`LF`) line endings when cloned on Windows.

### Changed
- **Local Development Defaults**: `Makefile` commands now use `.env.local` by default, allowing local image builds to run out of the box without conflicting with the pre-built GHCR image tags in `.env`.
- **Self-Contained Database Image**: Database initialization and performance-tuning scripts are now built directly into the `db` image, removing the need to mount local SQL or configuration files from the host.
- **Documentation & Environment Alignment**: Updated `README.md`, `AGENT.md`, `.env`, and `.env.local` to document all custom stylesheet and replication variables, local polygon mounting, and Mapnik 3.1 details.

### Fixed
- **Shared Volume Permissions & Database Access**: Fixed permission issues between Apache, the tile renderer, and the updater on shared tile cache and socket volumes, and ensured custom `PGPASSWORD` values stay synchronized across database roles.
- **Background Updater Stability**: Fixed missing dependencies and passed custom `osm2pgsql` and stylesheet settings through to the updater so regional diff updates and tile expiration run reliably.
- **CI Pipeline & Dependency Scanning**: Fixed a container scanning issue that caused Dependabot errors and improved end-to-end CI tests to verify that the background updater stays running.

---

## [3.0.2] - 2026-05-29

### Changed
- **Dedicated `linux/amd64` Builds**: Focused CI builds on `linux/amd64` for faster, more reliable builds and added the `db` image to the automated build, test, publish, and security scan pipeline.
- **Cleaner Dependency Updates**: Configured Dependabot to group Docker and GitHub Actions updates into weekly pull requests across all five services.
- **Actionable Vulnerability Reports**: Updated container vulnerability scans to report only issues that have an upstream fix available.

---

## [3.0.1] - 2026-05-23

### Added
- **Automated Service Startup Scripts**: Added startup and initialization scripts across all five services to handle database tuning, stylesheet compilation, data imports, and continuous updates automatically.
- **Flexible Image Tag Configuration**: Added image tag variables (`DB_IMAGE`, `IMPORT_IMAGE`, `RENDERD_IMAGE`, `WEB_IMAGE`, `UPDATER_IMAGE`) in `.env` and `.env.local` to switch easily between pre-built GHCR images and locally built images.

---

## [3.0.0] - 2026-05-23

This major release modernizes the OpenStreetMap Tile Server, moving from a single monolithic container to a modular Docker Compose microservices architecture.

> [!CAUTION]
> ### BREAKING CHANGE: Database Upgrade & Volume Recreation Required
> - **PostgreSQL 18 & PostGIS 3.6**: The database has been upgraded to PostgreSQL 18 and PostGIS 3.6.
> - **Incompatible Storage Formats**: PostgreSQL 18 data files are not compatible with earlier PostgreSQL versions.
> - **Action Required**: **You must recreate your Docker volumes from scratch.** Existing data in the `osm-db-data` volume will not load and must be re-imported.

### Added
- **Microservices Architecture**: Split the monolithic container into five dedicated services managed with `docker-compose.yml`:
  - `db`: PostgreSQL 18 + PostGIS 3.6 database tuned for geospatial workloads.
  - `import`: One-time data importer running `osm2pgsql`, `osmium-tool`, and `node-carto`.
  - `renderd`: Tile rendering daemon powered by Mapnik 3.1.
  - `web`: Apache2 web server with `mod_tile` and a built-in Leaflet v1.9.4 demo map.
  - `updater`: Background replication service using `osmosis` to keep map data and tiles up to date.
- **Environment File Configuration**: Added `.env` and `.env.local` files to configure ports, CPU threads, database passwords, download URLs, and memory settings in one place.
- **Database Performance Tuning**: Added automatic PostgreSQL tuning on startup (increased shared buffers, 10GB WAL limit, and disabled JIT) for faster imports and tile rendering.
- **GitHub Actions CI/CD**: Added automated workflows to build, test, sign (via Sigstore Cosign), scan, and publish container images to GitHub Container Registry (`ghcr.io`).
- **Modern `osm2pgsql` Flex Output**: Migrated data imports to the `osm2pgsql` flex backend using `openstreetmap-carto-flex.lua` and the OpenStreetMap Carto v6.0.0 stylesheet.
- **Incremental Imports**: The importer now detects if a database already exists and automatically switches to `--append` mode so additional regions can be imported without wiping existing data.
- **Supply-Chain Security**: Added OpenSSF Scorecard analysis and GitHub Dependency Review checks.
- **Container Metadata & Documentation**: Added standard OCI image labels and created [AGENT.md](AGENT.md) with an architectural overview of the project.

### Changed
- **Ubuntu 24.04 LTS Base**: Upgraded all service images to Ubuntu 24.04 LTS for newer packages and security updates.
- **Non-Root Service Execution**: Updated the database access, rendering daemon, and background updater to run under a dedicated non-privileged `_renderd` user and group.
- **Refreshed Documentation**: Rewrote [README.md](README.md) with step-by-step quickstart guides for both `make` and `docker compose`.

### Fixed
- **Script Line Endings**: Fixed Windows (`CRLF`) line-ending issues in container shell scripts that could cause startup failures on Linux.
- **Package Cleanup**: Streamlined `libapache2-mod-tile` installation and fixed broken `osmosis-db_replag` symlinks.
- **Workflow Hardening**: Disabled credential persistence during Git checkouts in GitHub Actions workflows.

---

[3.1.0]: https://github.com/Harvester57/openstreetmap-tile-server/compare/v3.0.2...v3.1.0
[3.0.2]: https://github.com/Harvester57/openstreetmap-tile-server/compare/v3.0.1...v3.0.2
[3.0.1]: https://github.com/Harvester57/openstreetmap-tile-server/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/Harvester57/openstreetmap-tile-server/compare/v2.4.2...v3.0.0
