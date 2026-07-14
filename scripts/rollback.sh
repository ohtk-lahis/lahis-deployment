#!/usr/bin/env bash
# LAHIS app rollback (step 7) — restore previous RELEASE pins for api/celery/ms
#
# Usage (from /opt/lahis):
#   ./scripts/rollback.sh              # use RELEASE.prev
#   ./scripts/rollback.sh RELEASE.history/RELEASE.20260101T120000Z
#
# Does not migrate or touch data volumes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

PREV_FILE="${1:-RELEASE.prev}"
SERVICES="${SERVICES:-api celery ms}"
# shellcheck disable=SC2206
SERVICE_ARR=(${SERVICES})

require_env_marker
load_dotenv
with_deploy_lock
require_file "${PREV_FILE}"

log "manual rollback from ${PREV_FILE}"
snapshot_release
cp -a "${PREV_FILE}" RELEASE
load_release RELEASE
export_images
if ! images_are_safe; then
  warn "rollback target uses :latest; set ALLOW_LATEST=1 to allow, or pin digests"
  die "refusing rollback to floating :latest without ALLOW_LATEST=1"
fi

log "IMAGE_API=${IMAGE_API}"
log "IMAGE_MS=${IMAGE_MS}"

compose pull "${SERVICE_ARR[@]}"
compose up -d --no-deps --force-recreate "${SERVICE_ARR[@]}"

if wait_for_app_health; then
  log "rollback succeeded"
  {
    echo "---"
    echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "result=manual_rollback_ok"
    echo "from=${PREV_FILE}"
    echo "IMAGE_API=${IMAGE_API}"
    echo "IMAGE_MS=${IMAGE_MS}"
  } >>deploy.log
  exit 0
fi

die "rollback health failed — check docker compose logs api ms celery"
