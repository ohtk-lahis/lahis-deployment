#!/usr/bin/env bash
# LAHIS MinIO restore from a backup mirror directory (step 8 companion)
#
# Usage:
#   CONFIRM=RESTORE ./scripts/restore-minio.sh /data/backups/minio-YYYYMMDDTHHMMSSZ
#
# Expects mirror layout from backup.sh (bucket contents under the directory).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

SRC="${1:-}"
[[ -n "${SRC}" && -d "${SRC}" ]] || die "usage: $0 /data/backups/minio-<timestamp>"

load_dotenv
require_env_marker

BUCKET="${MINIO_BUCKET:-${AWS_STORAGE_BUCKET_NAME:-lahis-media}}"
MC_IMAGE="${MC_IMAGE:-minio/mc:latest}"
NETWORK="${MINIO_DOCKER_NETWORK:-lahis}"
CONFIRM="${CONFIRM:-}"

[[ -n "${MINIO_ROOT_USER:-}" && -n "${MINIO_ROOT_PASSWORD:-}" ]] || die "MINIO_ROOT_* required in .env"

echo "DESTRUCTIVE-ish: mirror host files → minio/${BUCKET} from ${SRC}"
if [[ "${CONFIRM}" != "RESTORE" ]]; then
  echo "Re-run with: CONFIRM=RESTORE $0 ${SRC}"
  exit 2
fi

compose up -d minio

# Resolve path inside container: prefer SRC/BUCKET or SRC itself
MIRROR_SUB="${BUCKET}"
if [[ ! -d "${SRC}/${BUCKET}" ]]; then
  MIRROR_SUB="."
fi

log "mirroring ${SRC}/${MIRROR_SUB} → minio/${BUCKET}"
docker run --rm \
  --network "${NETWORK}" \
  -v "${SRC}:/backup:ro" \
  --entrypoint /bin/sh \
  "${MC_IMAGE}" \
  -c "
    mc alias set lahis http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' &&
    mc mb --ignore-existing lahis/${BUCKET} &&
    mc mirror --overwrite /backup/${MIRROR_SUB} lahis/${BUCKET}
  "

log "MinIO restore mirror finished"
