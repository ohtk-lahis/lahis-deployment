#!/usr/bin/env bash
# Create MinIO bucket (and optional public-read) for LAHIS one-box stack.
# Contract: ../CONTRACT.md
#
# Prerequisites:
#   - docker compose project with healthy minio
#   - .env with MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, MINIO_BUCKET (or AWS_STORAGE_BUCKET_NAME)
#
# Usage (from deploy root, e.g. /opt/lahis):
#   ./scripts/bootstrap-minio.sh
#   PUBLIC_READ=1 ./scripts/bootstrap-minio.sh   # anonymous download on bucket (demo only)

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
PUBLIC_READ="${PUBLIC_READ:-0}"
MC_IMAGE="${MC_IMAGE:-minio/mc:latest}"

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

if [[ "${PUBLIC_READ}" == "1" ]]; then
  log "setting anonymous download on bucket (PUBLIC_READ=1)"
  docker run --rm --network "${NETWORK}" \
    --entrypoint /bin/sh \
    "${MC_IMAGE}" \
    -c "
      mc alias set lahis http://minio:9000 '${ROOT_USER}' '${ROOT_PASSWORD}' &&
      mc anonymous set download lahis/${BUCKET}
    "
  log "consider AWS_QUERYSTRING_AUTH=False in .env when using public custom domain URLs"
else
  log "bucket left private (default). App uses signed URLs unless you set PUBLIC_READ=1"
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
  public:     https://\${MINIO_PUBLIC_HOST:-minio.lahis.ohtk.org} (via proxy)

App .env should include:
  USE_S3=True
  AWS_S3_ENDPOINT_URL=http://minio:9000
  AWS_S3_ADDRESSING_STYLE=path
  AWS_S3_USE_SSL=False
  AWS_STORAGE_BUCKET_NAME=${BUCKET}
  AWS_ACCESS_KEY_ID=...
  AWS_SECRET_ACCESS_KEY=...
  AWS_S3_CUSTOM_DOMAIN=\${MINIO_PUBLIC_HOST:-minio.lahis.ohtk.org}

EOF
