#!/usr/bin/env bash
# LAHIS Postgres restore (step 8) — DESTRUCTIVE to the database contents
#
# Usage (from /opt/lahis):
#   ./scripts/restore-pg.sh /data/backups/pg-YYYYMMDDTHHMMSSZ.sql.gz
#   CONFIRM=RESTORE ./scripts/restore-pg.sh /data/backups/pg-....sql.gz
#
# Stops api + celery (writers), restores dump into DB, starts api + celery again.
# Does NOT restore MinIO objects (restore those separately if needed).
# Does NOT run migrations (restored dump should already match app schema intent).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

DUMP="${1:-}"
[[ -n "${DUMP}" ]] || die "usage: $0 /path/to/pg-....sql.gz"
[[ -f "${DUMP}" ]] || die "dump not found: ${DUMP}"
gzip -t "${DUMP}" || die "not a valid gzip: ${DUMP}"

load_dotenv
require_env_marker
with_deploy_lock

PG_USER="${POSTGRES_USER:-${DB_USER:-lahis}}"
PG_DB="${POSTGRES_DB:-${DB_NAME:-lahis}}"
CONFIRM="${CONFIRM:-}"

cat <<EOF
============================================================
DESTRUCTIVE: restore Postgres from dump
  dump:   ${DUMP}
  db:     ${PG_DB} (user ${PG_USER})
  host:   $(hostname 2>/dev/null || echo unknown)
  ENV:    $(tr -d '[:space:]' <ENV_NAME 2>/dev/null || echo unknown)
============================================================
This REPLACES current database contents for ${PG_DB}.
EOF

if [[ "${CONFIRM}" != "RESTORE" ]]; then
  echo
  echo "Re-run with:  CONFIRM=RESTORE $0 ${DUMP}"
  echo "Aborting (no changes)."
  exit 2
fi

log "stopping api and celery (leave db/redis/minio/proxy up)"
compose stop api celery || true

if ! compose exec -T db pg_isready -U "${PG_USER}" -d postgres >/dev/null 2>&1; then
  die "postgres not ready"
fi

log "terminating other connections to ${PG_DB}"
compose exec -T db psql -U "${PG_USER}" -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${PG_DB}' AND pid <> pg_backend_pid();
SQL

log "dropping and recreating database ${PG_DB}"
compose exec -T db psql -U "${PG_USER}" -d postgres -v ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS "${PG_DB}";
CREATE DATABASE "${PG_DB}" OWNER "${PG_USER}";
SQL

# PostGIS often required before/after restore depending on dump contents
log "ensuring postgis extension"
compose exec -T db psql -U "${PG_USER}" -d "${PG_DB}" -v ON_ERROR_STOP=1 \
  -c 'CREATE EXTENSION IF NOT EXISTS postgis;' || warn "postgis extension create failed (may already be in dump)"

log "restoring dump (this may take a while)"
gunzip -c "${DUMP}" | compose exec -T db psql -U "${PG_USER}" -d "${PG_DB}" -v ON_ERROR_STOP=1

log "starting api and celery"
# shellcheck disable=SC1091
if [[ -f RELEASE ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./RELEASE
  set +a
  export IMAGE_API IMAGE_MS
fi
compose up -d --no-deps api celery

if wait_for_app_health; then
  log "restore complete; app health ok"
else
  warn "restore finished but app health check failed — inspect logs"
  exit 1
fi

{
  echo "---"
  echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "result=restore_pg_ok"
  echo "dump=${DUMP}"
} >>deploy.log

log "done. Run ./scripts/smoke.sh when ready."
log "MinIO objects were NOT restored by this script."
