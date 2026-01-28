.PHONY: server setup deps db.reset db.migrate test

# Load .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

PORT ?= 4001

# Start the Phoenix server
server:
	PORT=$(PORT) mix phx.server

# Interactive server with IEx
console:
	PORT=$(PORT) iex -S mix phx.server

# Install dependencies
deps:
	mix deps.get

# Setup project (deps + database)
setup: deps
	mix ecto.setup

# Reset database
db.reset:
	mix ecto.reset

# Run migrations
db.migrate:
	mix ecto.migrate

# Run tests
test:
	mix test
