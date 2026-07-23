#!/usr/bin/env bash
# Create MinIO bucket for LAHIS one-box storage and enforce the selected media mode.
# Contract: ../CONTRACT.md
#
# Prerequisites:
#   - docker compose project with healthy minio
#   - .env with MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, MINIO_BUCKET (or AWS_STORAGE_BUCKET_NAME)
#
# Usage (from deploy root, e.g. /opt/lahis):
#   ./scripts/bootstrap-minio.sh
#   MINIO_PUBLIC_READ=0 ./scripts/bootstrap-minio.sh  # private bucket; do not set a public custom domain

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  echo "ERROR: ${ROOT}/.env missing" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
. ./.env
set +a

BUCKET="${MINIO_BUCKET:-${AWS_STORAGE_BUCKET_NAME:-lahis-media}}"
ROOT_USER="${MINIO_ROOT_USER:?MINIO_ROOT_USER required in .env}"
ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD required in .env}"
# compose.yml: networks.lahis.name = lahis
NETWORK="${MINIO_DOCKER_NETWORK:-lahis}"
PUBLIC_READ="${PUBLIC_READ:-${MINIO_PUBLIC_READ:-}}"
MC_IMAGE="${MC_IMAGE:-minio/mc:latest}"
PUBLIC_DOMAIN="${AWS_S3_CUSTOM_DOMAIN:-}"
EXPECTED_PUBLIC_DOMAIN="${MINIO_PUBLIC_HOST:-minio.lahis.ohtk.org}/${BUCKET}"
SENTINEL_KEY="media/.lahis-public-read-check"

log() { printf '+ %s\n' "$*"; }

log "ensuring minio is up"
docker compose up -d minio

log "waiting for minio health"
for i in $(seq 1 30); do
  if docker compose exec -T minio curl -sf http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    echo "ERROR: minio not healthy" >&2
    exit 1
  fi
  sleep 2
done

log "creating bucket '${BUCKET}' (ignore if exists)"
docker run --rm --network "${NETWORK}" \
  --entrypoint /bin/sh \
  "${MC_IMAGE}" \
  -c "
    mc alias set lahis http://minio:9000 '${ROOT_USER}' '${ROOT_PASSWORD}' &&
    mc mb --ignore-existing lahis/${BUCKET} &&
    mc ls lahis/${BUCKET}
  "

if [[ -n "${PUBLIC_DOMAIN}" ]]; then
  [[ "${PUBLIC_DOMAIN}" == "${EXPECTED_PUBLIC_DOMAIN}" ]] || {
    echo "ERROR: AWS_S3_CUSTOM_DOMAIN must be '${EXPECTED_PUBLIC_DOMAIN}' for path-style public media" >&2
    exit 1
  }
  [[ "${PUBLIC_READ}" == "1" ]] || {
    echo "ERROR: public AWS_S3_CUSTOM_DOMAIN requires MINIO_PUBLIC_READ=1 (or unset AWS_S3_CUSTOM_DOMAIN for private media)" >&2
    exit 1
  }
fi

if [[ "${PUBLIC_READ}" == "1" ]]; then
  log "setting anonymous download on bucket (MINIO_PUBLIC_READ=1)"
  docker run --rm --network "${NETWORK}" \
    --entrypoint /bin/sh \
    "${MC_IMAGE}" \
    -c "
      mc alias set lahis http://minio:9000 '${ROOT_USER}' '${ROOT_PASSWORD}' &&
      mc anonymous set download lahis/${BUCKET}
    "
  log "writing public-media sentinel ${SENTINEL_KEY}"
  printf 'lahis public media access check\n' | docker run --rm -i --network "${NETWORK}" \
    --entrypoint /bin/sh \
    "${MC_IMAGE}" \
    -c "
      mc alias set lahis http://minio:9000 '${ROOT_USER}' '${ROOT_PASSWORD}' &&
      mc pipe lahis/${BUCKET}/${SENTINEL_KEY} >/dev/null
    "
  anonymous_policy="$(docker run --rm --network "${NETWORK}" \
    --entrypoint /bin/sh \
    "${MC_IMAGE}" \
    -c "
      mc alias set lahis http://minio:9000 '${ROOT_USER}' '${ROOT_PASSWORD}' >/dev/null &&
      mc anonymous get lahis/${BUCKET}
    ")"
  [[ "${anonymous_policy}" == *"download"* ]] || {
    echo "ERROR: bucket '${BUCKET}' is not anonymously downloadable after bootstrap" >&2
    exit 1
  }
else
  [[ -z "${PUBLIC_DOMAIN}" ]] || exit 1
  log "bucket left private; public custom-domain URLs are disabled"
fi

# Optional: ensure app access key exists as MinIO user (if different from root)
APP_KEY="${AWS_ACCESS_KEY_ID:-}"
APP_SECRET="${AWS_SECRET_ACCESS_KEY:-}"
if [[ -n "${APP_KEY}" && -n "${APP_SECRET}" && "${APP_KEY}" != "${ROOT_USER}" ]]; then
  log "ensuring MinIO user for app key ${APP_KEY}"
  if ! docker run --rm --network "${NETWORK}" \
    --entrypoint /bin/sh \
    "${MC_IMAGE}" \
    -c "
      mc alias set lahis http://minio:9000 '${ROOT_USER}' '${ROOT_PASSWORD}' &&
      (mc admin user info lahis '${APP_KEY}' >/dev/null 2>&1 ||
        mc admin user add lahis '${APP_KEY}' '${APP_SECRET}') &&
      (mc admin policy attach lahis readwrite --user '${APP_KEY}' || true)
    "; then
    echo "! could not configure app user; for lab set AWS_ACCESS_KEY_ID/SECRET to MINIO_ROOT_*" >&2
  fi
fi

cat <<EOF

MinIO bootstrap done.
  bucket:     ${BUCKET}
  endpoint:   http://minio:9000 (compose)
  public:     https://\${MINIO_PUBLIC_HOST:-minio.lahis.ohtk.org}/${BUCKET} (via proxy)

App .env should include:
  USE_S3=True
  AWS_S3_ENDPOINT_URL=http://minio:9000
  AWS_S3_ADDRESSING_STYLE=path
  AWS_S3_USE_SSL=False
  AWS_STORAGE_BUCKET_NAME=${BUCKET}
  AWS_ACCESS_KEY_ID=...
  AWS_SECRET_ACCESS_KEY=...
  AWS_S3_CUSTOM_DOMAIN=\${MINIO_PUBLIC_HOST:-minio.lahis.ohtk.org}/${BUCKET}
  AWS_QUERYSTRING_AUTH=False
  MINIO_PUBLIC_READ=1

EOF
