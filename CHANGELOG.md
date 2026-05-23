# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [3.0.0] - 2026-05-23

This is a major release representing a complete modernization and modularization of the OpenStreetMap Tile Server repository, moving from a monolithic single-container setup to a highly optimized, production-ready microservices architecture based on Docker Compose.

> [!CAUTION]
> ### 🚨 BREAKING CHANGE: Database Upgrade & Volume Recreation Required
> - **PostgreSQL 18 & PostGIS 3.6**: The database layer has been upgraded to PostgreSQL 18 and PostGIS 3.6.
> - **Incompatible Storage Formats**: The internal database storage structure of PostgreSQL 18 is incompatible with previous versions (which used older PostgreSQL versions).
> - **Action Required**: **You MUST recreate all your Docker volumes from scratch.** Any existing data stored in the `osm-db-data` volume is incompatible and will fail to load.

### Added
- **Modular Microservices Architecture**: Decoupled the monolithic single-container setup into five dedicated microservices managed via `docker-compose.yml`:
  - `db`: High-performance custom PostgreSQL 18 + PostGIS 3.6 database container.
  - `import`: Short-lived, high-speed import environment running `osm2pgsql`, `osmosis`, and `osmium-tool`.
  - `renderd`: Map rendering daemon compiled with Mapnik 3.0.
  - `web`: Apache2 front-end web server serving tiles with `mod_tile` and an interactive Leaflet v1.9.4 map.
  - `updater`: Continuous background replication engine utilizing `osmosis`.
- **Environment Variables Support**: Introduced a standard `.env` configuration file along with a local developer override `.env.local`, enabling flexible custom setup of postgres passwords, execution threads, custom download URLs, port mappings, and performance tuning parameters.
- **Automated Database Performance Tuning**: Created robust startup configuration templates (`postgresql.custom.conf.tmpl` and `10-optimize-db.sh`) that dynamically optimize shared buffers, disabling JIT compilation, WAL size, and autovacuum features for intense geospatial write actions.
- **GitHub Actions Workflows (CI/CD)**: Added standard GitHub Actions pipelines for multi-architecture building (`amd64` / `arm64`), automated testing, and secure container image deployment to the GitHub Container Registry (`ghcr.io`).
- **Flex Schema / lua Style Support**: Fully migrated the container importing logic to modern `osm2pgsql` flex output using `openstreetmap-carto-flex.lua` and OpenStreetMap Carto v6.0.0 stylesheet.
- **Automatic Appending Imports**: Added logic to automatically detect existing database structures and run `osm2pgsql` in `--append` mode instead of `--create` for incremental data loads.
- **Supply-Chain Security Audits**: Integrated OpenSSF Scorecard workflows for supply chain security analysis and Dependency Review triggers to scan for vulnerable dependencies.
- **OCI Image Metadata**: Attached industry-standard OCI (Open Container Initiative) labels directly to the container build specifications.
- **New Onboarding Documentation**: Created [AGENT.md](file:///c:/Users/Florian/OneDrive/Documents/Dev/openstreetmap-tile-server/AGENT.md) providing pairing guides, repository structures, and system overviews.

### Changed
- **Base OS Upgrade**: Upgraded all Docker images to use **Ubuntu 24.04 LTS** as the base system, leveraging updated libraries and modern compiler binaries.
- **Standardized Permissions**: Restored standard security controls by mapping database access, the web server, the rendering engine, and the background crons to run under a non-privileged `_renderd` system user with synchronized UID/GID values.
- **Simplified Instructions**: Overhauled and cleaned up [README.md](README.md) to focus on quick-start workflows using `make` commands or native Docker Compose syntax.

### Fixed
- **Line Ending Standardisation**: Resolved CRLF vs LF line ending bugs across container shell files, avoiding Linux execution errors during volume mounting.
- **Dependency Consolidation**: Cleaned up modular system package dependencies by organizing `libapache2-mod-tile` installation patterns and fixing broken symlinks for `osmosis-db_replag`.
- **Hardened GitHub workflows**: Disabled credential persistence for actions checkout steps in standard CI workflows.

---

[3.0.0]: https://github.com/Harvester57/openstreetmap-tile-server/compare/v2.4.2...HEAD
