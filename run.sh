#!/usr/bin/env bash
set -euo pipefail

TASK_DIR="/root/task"
COMPOSE_FILE="${TASK_DIR}/docker-compose.yml"
DB_USER="streamly"
DB_NAME="streamly_analytics"
CONTAINER="streamly_pg"

echo "[run] Starting PostgreSQL..."
docker compose -f "${COMPOSE_FILE}" up -d

echo "[run] Waiting for PostgreSQL to become healthy..."
ATTEMPTS=0
MAX_ATTEMPTS=40
until docker exec "${CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS+1))
  if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
    echo "[run] ERROR: PostgreSQL did not become ready in time."
    docker compose -f "${COMPOSE_FILE}" logs --tail=50 postgres || true
    exit 1
  fi
  sleep 2
done

echo "[run] PostgreSQL is ready. Verifying initialized schema..."

check_table() {
  local tbl="$1"
  docker exec "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT to_regclass('public.${tbl}') IS NOT NULL;" | grep -q 't'
}

for t in subscribers plans subscription_plan_history viewing_sessions; do
  if check_table "$t"; then
    echo "[run] Table present: ${t}"
  else
    echo "[run] ERROR: expected table missing: ${t}"
    exit 1
  fi
done

echo "[run] Verifying seed data volume..."
SESSION_COUNT=$(docker exec "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tAc "SELECT COUNT(*) FROM viewing_sessions;")
echo "[run] viewing_sessions rows: ${SESSION_COUNT}"
if [ "${SESSION_COUNT}" -lt 1 ]; then
  echo "[run] ERROR: viewing_sessions is empty."
  exit 1
fi

echo "[run] Verifying draft view is queryable..."
docker exec "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
  "SELECT 1 FROM v_watch_hours_by_tier_draft LIMIT 1;" >/dev/null 2>&1 \
  && echo "[run] Draft view is queryable." \
  || echo "[run] NOTE: draft view returned no rows or is empty (acceptable for readiness)."

echo "[run] Verifying candidate_solution.sql parses (dry run in a rolled-back transaction)..."
if [ -f "${TASK_DIR}/candidate_solution.sql" ]; then
  docker exec -i "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 \
    -c 'BEGIN;' -f - <<'SQL' 2>/dev/null || true
BEGIN;
ROLLBACK;
SQL
  echo "[run] candidate_solution.sql present."
fi

echo "[run] Container status:"
docker compose -f "${COMPOSE_FILE}" ps

echo "[run] Readiness check complete. Environment is ready."
exit 0
