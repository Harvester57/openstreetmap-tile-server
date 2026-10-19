.PHONY: build import start start-with-updates stop logs status clean

ENV_FILE ?= .env.local
COMPOSE = docker compose --env-file $(ENV_FILE)

# Build all microservices targets concurrently
build:
	$(COMPOSE) build

# Trigger the short-lived importer service to load map data (downloads Luxembourg by default)
import:
	$(COMPOSE) run --rm import

# Start the serving infrastructure (web, renderd, db)
start:
	$(COMPOSE) up -d web

# Start the serving infrastructure with updates (web, renderd, db, updater)
start-with-updates:
	$(COMPOSE) up -d web updater

# View logs from all running microservices
logs:
	$(COMPOSE) logs -f

# View status of running services
status:
	$(COMPOSE) ps

# Stop all microservices
stop:
	$(COMPOSE) down

# Clean up all containers, networks, and named volumes
clean:
	$(COMPOSE) down -v

