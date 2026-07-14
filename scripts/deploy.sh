#!/usr/bin/env bash
# LAHIS app deploy (step 7) — api + celery + ms only
# Does NOT migrate, touch db/redis/minio volumes, or restart proxy by default.
#
# Usage (from /opt/lahis):
#   ./scripts/deploy.sh
#       Deploy images currently listed in ./RELEASE
#   ./scripts/deploy.sh --api ghcr.io/...@sha256:... --ms public.ecr.aws/...@sha256:...
#       Write RELEASE then deploy
#   ALLOW_LATEST=1 ./scripts/deploy.sh
#       Allow :latest tags (lab only)
#   NO_ROLLBACK=1 ./scripts/deploy.sh
#       Do not auto-restore RELEASE.prev on health failure
#   SERVICES="api celery ms" HEALTH_TIMEOUT=180 ./scripts/deploy.sh
#
# Safety:
#   - flock .deploy.lock
#   - requires ENV_NAME marker (default staging)
#   - refuses :latest unless ALLOW_LATEST=1
#   - never docker compose down -v

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

NEW_API=""
NEW_MS=""
SERVICES="${SERVICES:-api celery ms}"
# shellcheck disable=SC2206
SERVICE_ARR=(${SERVICES})

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api)
      NEW_API="${2:-}"
      shift 2
      ;;
    --ms)
      NEW_MS="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      die "unknown arg: $1 (see --help)"
      ;;
  esac
done

require_env_marker
load_dotenv
with_deploy_lock

if [[ -n "${NEW_API}" || -n "${NEW_MS}" ]]; then
  [[ -n "${NEW_API}" && -n "${NEW_MS}" ]] || die "both --api and --ms are required when specifying images"
  # Snapshot currently recorded pins before overwriting RELEASE
  snapshot_release
  write_release "${NEW_API}" "${NEW_MS}"
else
  require_file RELEASE
  # Redeploy whatever is already in RELEASE (restart / re-pull).
  # To change pins safely, prefer --api/--ms so RELEASE.prev stays the previous pins.
  # If you hand-edited RELEASE, copy the old file to RELEASE.prev yourself first.
  if [[ ! -f RELEASE.prev ]]; then
    snapshot_release
  else
    log "keeping existing RELEASE.prev; redeploying IMAGE pins from RELEASE"
    mkdir -p RELEASE.history
    cp -a RELEASE "RELEASE.history/RELEASE.$(date -u +%Y%m%dT%H%M%SZ).target"
  fi
fi

load_release RELEASE
export_images
assert_images_safe

log "deploy target:"
log "  IMAGE_API=${IMAGE_API}"
log "  IMAGE_MS=${IMAGE_MS}"
log "  services: ${SERVICE_ARR[*]}"

log "pulling images"
compose pull "${SERVICE_ARR[@]}"

log "recreating app services"
compose up -d --no-deps --force-recreate "${SERVICE_ARR[@]}"

if wait_for_app_health; then
  log "deploy succeeded"
  {
    echo "---"
    echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "result=success"
    echo "IMAGE_API=${IMAGE_API}"
    echo "IMAGE_MS=${IMAGE_MS}"
  } >>deploy.log
  exit 0
fi

warn "health check failed after deploy"
{
  echo "---"
  echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "result=health_failed"
  echo "IMAGE_API=${IMAGE_API}"
  echo "IMAGE_MS=${IMAGE_MS}"
} >>deploy.log

if [[ "${NO_ROLLBACK:-0}" == "1" ]]; then
  die "health failed and NO_ROLLBACK=1 — manual recovery required"
fi

if [[ ! -f RELEASE.prev ]]; then
  die "health failed and no RELEASE.prev — cannot auto-rollback"
fi

warn "auto-rollback to RELEASE.prev"
restore_release_prev
if ! images_are_safe; then
  warn "previous RELEASE uses :latest; continuing rollback with ALLOW_LATEST semantics"
  ALLOW_LATEST=1
fi
compose pull "${SERVICE_ARR[@]}" || warn "pull during rollback had errors"
compose up -d --no-deps --force-recreate "${SERVICE_ARR[@]}"

if wait_for_app_health; then
  warn "rollback restored healthy previous images"
  {
    echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "result=rolled_back_ok"
    echo "IMAGE_API=${IMAGE_API}"
    echo "IMAGE_MS=${IMAGE_MS}"
  } >>deploy.log
  exit 1
fi

die "rollback also failed health checks — inspect: docker compose ps && docker compose logs api ms celery"
