#!/bin/bash
# Start Pipeline - Start Postgres, run DB migrations safely, then start GoClaw

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.goclaw.yml"

# Remove obsolete compose 'version' key if present (Compose v2 ignores it)
sed -i.bak '/^version:/d' "$COMPOSE_FILE" 2>/dev/null || true

# Ensure .env exists
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
  echo "Error: ${PROJECT_ROOT}/.env not found.\nCreate it with: cp .env.example .env" >&2
  exit 1
fi

echo "Starting pipeline services..."

# 1) Start only Postgres first
echo "Starting PostgreSQL..."}
docker compose -f "$COMPOSE_FILE" up -d postgres

# 2) Wait for Postgres to be healthy (max ~60s)
POSTGRES_CONTAINER="goclaw-postgres"
for i in {1..30}; do
  status=$(docker inspect -f '{{.State.Health.Status}}' "$POSTGRES_CONTAINER" 2>/dev/null || echo "unknown")
  if [[ "$status" == "healthy" ]]; then
    echo "PostgreSQL is healthy."
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "PostgreSQL did not become healthy in time (status=$status)." >&2
    docker logs --tail=100 "$POSTGRES_CONTAINER" || true
    exit 1
  fi
  sleep 2
  echo "Waiting for PostgreSQL to be healthy... ($((i*2))s)"
done

# 3) Run migrations in an ephemeral container (do not rely on restarting service)
set +e

echo "Checking GoClaw DB schema status..."
docker compose -f "$COMPOSE_FILE" run --rm --no-deps goclaw goclaw upgrade --status
status_exit=$?
set -e

if [[ $status_exit -ne 0 ]]; then
  echo "Schema dirty/mismatched. Forcing baseline to 0 and upgrading..."
  # Force baseline and upgrade, using ephemeral runs
  docker compose -f "$COMPOSE_FILE" run --rm --no-deps -e GOCLAW_OPENAI_API_KEY -e GOCLAW_MINIMAX_API_KEY -e GOCLAW_TELEGRAM_BOT_TOKEN -e GOCLAW_TELEGRAM_CHAT_ID -e GOCLAW_POSTGRES_DSN goclaw goclaw migrate force 0 || true
  docker compose -f "$COMPOSE_FILE" run --rm --no-deps -e GOCLAW_OPENAI_API_KEY -e GOCLAW_MINIMAX_API_KEY -e GOCLAW_TELEGRAM_BOT_TOKEN -e GOCLAW_TELEGRAM_CHAT_ID -e GOCLAW_POSTGRES_DSN goclaw goclaw upgrade
fi

# 4) Start GoClaw service
echo "Starting GoClaw service..."
set +e
docker compose -f "$COMPOSE_FILE" up -d goclaw
up_exit=$?
set -e

if [[ $up_exit -ne 0 ]]; then
  echo "Failed to start GoClaw (exit=$up_exit). Diagnostics:"
  docker ps --all --filter 'name=goclaw-pipeline'
  docker logs --tail=200 goclaw-pipeline || true
  exit $up_exit
fi

# 5) Show status and URLs
echo ""
echo "=========================================="
echo "Pipeline Services Status"
echo "=========================================="
if command -v systemctl &>/dev/null; then
  echo "Redis: $(systemctl is-active redis-server || echo 'n/a')"
fi
echo "Postgres: $(docker inspect -f '{{.State.Status}}' "$POSTGRES_CONTAINER" 2>/dev/null || echo 'unknown')"
echo "GoClaw: $(docker ps --filter 'name=goclaw-pipeline' --format '{{.Status}}')"
echo ""
echo "GoClaw Dashboard: http://localhost:18789"
echo "=========================================="
