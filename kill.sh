#!/usr/bin/env bash
set -e

COMPOSE_FILE="/root/task/docker-compose.yml"

echo "Stopping containers and removing compose resources..."
docker compose -f "${COMPOSE_FILE}" down --volumes --remove-orphans || true

echo "Removing named volume (if present)..."
docker volume rm streamly_pgdata || true

echo "Removing network (if present)..."
docker network rm streamly_net || true

echo "Pruning dangling Docker resources..."
docker system prune -a --volumes -f || true

echo "Removing related PostgreSQL images..."
docker rmi -f $(docker images -q | grep -E 'postgres:15-alpine|postgres:16-alpine' || true) || true

echo "Deleting task folder..."
rm -rf /root/task || true

echo "Cleanup completed successfully! Droplet is now clean."
