.PHONY: build import start start-with-updates stop logs status clean

# Build all microservices targets concurrently
build:
	docker compose build

# Trigger the short-lived importer service to load map data (downloads Luxembourg by default)
import:
	docker compose run --rm import

# Start the serving infrastructure (web, renderd, db)
start:
	docker compose up -d web

# Start the serving infrastructure with updates (web, renderd, db, updater)
start-with-updates:
	docker compose up -d web updater

# View logs from all running microservices
logs:
	docker compose logs -f

# View status of running services
status:
	docker compose ps

# Stop all microservices
stop:
	docker compose down

# Clean up all containers, networks, and named volumes
clean:
	docker compose down -v
