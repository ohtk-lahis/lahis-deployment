# shellcheck shell=bash
# Shared helpers for LAHIS deploy scripts. Source from scripts/*.sh only.

lahis_root() {
  cd "$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  pwd
}

log() { printf '+ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

load_dotenv() {
  require_file .env
  # shellcheck disable=SC1091
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
}

load_release() {
  local file="${1:-RELEASE}"
  require_file "${file}"
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1090
  . "./${file}"
  set +a
  [[ -n "${IMAGE_API:-}" ]] || die "${file}: IMAGE_API empty"
  [[ -n "${IMAGE_MS:-}" ]] || die "${file}: IMAGE_MS empty"
}

export_images() {
  export IMAGE_API IMAGE_MS
}

image_looks_floating_latest() {
  case "$1" in
    *:latest | */latest) return 0 ;;
    *) return 1 ;;
  esac
}

images_are_safe() {
  local allow_latest="${ALLOW_LATEST:-0}"
  if image_looks_floating_latest "${IMAGE_API}" || image_looks_floating_latest "${IMAGE_MS}"; then
    if [[ "${allow_latest}" != "1" ]]; then
      return 1
    fi
    warn "ALLOW_LATEST=1: deploying floating :latest tags"
  fi
  return 0
}

assert_images_safe() {
  if ! images_are_safe; then
    die "IMAGE_API/IMAGE_MS use floating :latest — pin a digest (or ALLOW_LATEST=1 for lab only)"
  fi
}

require_env_marker() {
  local expected="${ENV_NAME:-staging}"
  require_file ENV_NAME
  local got
  got="$(tr -d '[:space:]' <ENV_NAME)"
  [[ "${got}" == "${expected}" ]] || die "ENV_NAME is '${got}', expected '${expected}' (refusing deploy)"
}

with_deploy_lock() {
  local lock="${DEPLOY_LOCK:-.deploy.lock}"
  exec 9>"${lock}"
  if ! flock -n 9; then
    die "another deploy holds ${lock}"
  fi
  log "acquired lock ${lock}"
}

compose() {
  docker compose "$@"
}

api_health_ok() {
  compose exec -T api python -c \
    "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5); assert r.read()==b'ok'" \
    >/dev/null 2>&1
}

ms_health_ok() {
  # Next standalone listens on 3000. Prefer 127.0.0.1 when HOSTNAME=0.0.0.0;
  # also accept reachability via the service name (works even if Next bound to
  # Docker's container-id hostname only).
  compose exec -T ms wget -q -O /dev/null http://127.0.0.1:3000/ 2>/dev/null \
    || compose exec -T ms node -e "require('http').get('http://127.0.0.1:3000/',r=>process.exit(r.statusCode?0:1)).on('error',()=>process.exit(1))" \
    >/dev/null 2>&1 \
    || compose exec -T proxy wget -q -O /dev/null http://ms:3000/ 2>/dev/null \
    || compose exec -T api python -c \
      "import urllib.request; urllib.request.urlopen('http://ms:3000/', timeout=5)" \
      >/dev/null 2>&1
}

celery_running_ok() {
  compose ps --status running --services 2>/dev/null | grep -qx celery \
    || compose ps 2>/dev/null | grep -E 'celery' | grep -qiE 'up|running'
}

wait_for_app_health() {
  local timeout="${HEALTH_TIMEOUT:-120}"
  local interval="${HEALTH_INTERVAL:-5}"
  local elapsed=0
  log "waiting for app health (timeout=${timeout}s)"
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    local api_ok=0 ms_ok=0 celery_ok=0
    api_health_ok && api_ok=1
    ms_health_ok && ms_ok=1
    celery_running_ok && celery_ok=1
    if [[ "${api_ok}" -eq 1 && "${ms_ok}" -eq 1 && "${celery_ok}" -eq 1 ]]; then
      log "health ok (api + ms + celery)"
      return 0
    fi
    sleep "${interval}"
    elapsed=$((elapsed + interval))
    log "still waiting... ${elapsed}s (api=${api_ok} ms=${ms_ok} celery=${celery_ok})"
  done
  return 1
}

snapshot_release() {
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p RELEASE.history
  if [[ -f RELEASE ]]; then
    cp -a RELEASE "RELEASE.history/RELEASE.${ts}"
    cp -a RELEASE RELEASE.prev
    log "snapshot RELEASE → RELEASE.prev and RELEASE.history/RELEASE.${ts}"
  else
    warn "no existing RELEASE to snapshot"
  fi
}

write_release() {
  local api="$1"
  local ms="$2"
  cat >RELEASE <<EOF
# Written by deploy.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ)
IMAGE_API=${api}
IMAGE_MS=${ms}
EOF
  log "wrote RELEASE"
  cat RELEASE
}

restore_release_prev() {
  require_file RELEASE.prev
  cp -a RELEASE.prev RELEASE
  load_release RELEASE
  export_images
  log "restored RELEASE from RELEASE.prev"
  cat RELEASE
}
