#!/usr/bin/env bash
# LAHIS gated schema migration (step 4 companion)
# Runs migrate_schemas inside a one-off api container. Does not start the web stack.
#
# Usage (from /opt/lahis or this repo dir):
#   ./scripts/migrate.sh              # apply
#   ./scripts/migrate.sh --plan       # show plan only (no apply)
#
# Requires: docker compose, .env, healthy/accessible db (compose network).
# Prefer running after: docker compose up -d db redis

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  echo "ERROR: ${ROOT}/.env missing (copy from .env.example)" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
# RELEASE may define IMAGE_API
[[ -f RELEASE ]] && . ./RELEASE
set +a

PLAN_ONLY=0
if [[ "${1:-}" == "--plan" ]]; then
  PLAN_ONLY=1
fi

echo "Using IMAGE_API=${IMAGE_API:-default from compose}"

if [[ "${PLAN_ONLY}" -eq 1 ]]; then
  echo "=== migrate_schemas --plan (no apply) ==="
  echo "Note: on a brand-new empty DB, --plan can fail before tenants_client exists."
  echo "Prefer: apply with --shared first (see non-plan path), then --plan."
  docker compose run --rm --no-deps \
    -e RUN_MIGRATIONS=0 \
    --entrypoint python \
    api manage.py migrate_schemas --plan
  echo "Plan only. Re-run without --plan to apply."
  exit 0
fi

echo "=== migrate_schemas --noinput (APPLY) ==="
echo "Empty DB: runs --shared first, then all schemas."
echo "This mutates the database. Ctrl-C within 5s to abort."
sleep 5

# Shared apps first so tenants_client exists (django-tenants empty DB)
docker compose run --rm --no-deps \
  -e RUN_MIGRATIONS=0 \
  --entrypoint python \
  api manage.py migrate_schemas --shared --noinput

docker compose run --rm --no-deps \
  -e RUN_MIGRATIONS=0 \
  --entrypoint python \
  api manage.py migrate_schemas --noinput

echo "Migrations applied."
