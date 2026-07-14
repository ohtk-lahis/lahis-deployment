#!/usr/bin/env bash
# LAHIS backup (step 8) — Postgres dump + optional MinIO mirror + config snapshot
#
# Usage (from /opt/lahis):
#   ./scripts/backup.sh
#   SKIP_MINIO=1 ./scripts/backup.sh
#   RETAIN_DAYS=14 ./scripts/backup.sh
#
# Writes under ${DATA_ROOT}/backups (default /data/backups):
#   pg-YYYYMMDDTHHMMSSZ.sql.gz
#   minio-YYYYMMDDTHHMMSSZ/   (optional, via mc mirror)
#   meta-YYYYMMDDTHHMMSSZ.txt
#   config-YYYYMMDDTHHMMSSZ.tgz  (.env redacted, RELEASE, compose, proxy)
#
# Does NOT stop the stack. For a quieter dump, stop api/celery first (optional).
# Cron example (daily 02:15):
#   15 2 * * * cd /opt/lahis && ./scripts/backup.sh >>/var/log/lahis-backup.log 2>&1

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

load_dotenv

DATA_ROOT="${DATA_ROOT:-/data}"
BACKUP_ROOT="${BACKUP_ROOT:-${DATA_ROOT}/backups}"
RETAIN_DAYS="${RETAIN_DAYS:-14}"
SKIP_MINIO="${SKIP_MINIO:-0}"
MC_IMAGE="${MC_IMAGE:-minio/mc:latest}"
NETWORK="${MINIO_DOCKER_NETWORK:-lahis}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
PG_USER="${POSTGRES_USER:-${DB_USER:-lahis}}"
PG_DB="${POSTGRES_DB:-${DB_NAME:-lahis}}"
BUCKET="${MINIO_BUCKET:-${AWS_STORAGE_BUCKET_NAME:-lahis-media}}"

mkdir -p "${BACKUP_ROOT}"
log "backup root: ${BACKUP_ROOT} stamp=${TS}"

# --- Postgres ---
PG_FILE="${BACKUP_ROOT}/pg-${TS}.sql.gz"
log "pg_dump ${PG_DB} → ${PG_FILE}"
if ! compose exec -T db pg_isready -U "${PG_USER}" -d "${PG_DB}" >/dev/null 2>&1; then
  die "postgres not ready (is db up?)"
fi
compose exec -T db pg_dump -U "${PG_USER}" --no-owner --no-acl "${PG_DB}" \
  | gzip -c >"${PG_FILE}"
# basic integrity
gzip -t "${PG_FILE}"
PG_BYTES="$(wc -c <"${PG_FILE}" | tr -d ' ')"
[[ "${PG_BYTES}" -gt 100 ]] || die "pg dump suspiciously small (${PG_BYTES} bytes)"
log "postgres dump ok (${PG_BYTES} bytes)"

# --- MinIO (optional) ---
MINIO_DIR=""
if [[ "${SKIP_MINIO}" == "1" ]]; then
  log "SKIP_MINIO=1 — skip object store mirror"
elif [[ -z "${MINIO_ROOT_USER:-}" || -z "${MINIO_ROOT_PASSWORD:-}" ]]; then
  warn "MINIO_ROOT_* not set — skip MinIO mirror"
else
  MINIO_DIR="${BACKUP_ROOT}/minio-${TS}"
  mkdir -p "${MINIO_DIR}"
  log "mirroring minio bucket ${BUCKET} → ${MINIO_DIR}"
  # Mirror into a host bind via docker volume
  docker run --rm \
    --network "${NETWORK}" \
    -v "${MINIO_DIR}:/backup" \
    --entrypoint /bin/sh \
    "${MC_IMAGE}" \
    -c "
      mc alias set lahis http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' &&
      mc mirror --overwrite lahis/${BUCKET} /backup/${BUCKET} || mc mirror --overwrite lahis/${BUCKET} /backup/
    " || warn "MinIO mirror had errors (bucket empty or network?)"
  log "MinIO mirror finished"
fi

# --- Config snapshot (no secrets in plain text if we can help it) ---
CONFIG_TGZ="${BACKUP_ROOT}/config-${TS}.tgz"
META_FILE="${BACKUP_ROOT}/meta-${TS}.txt"
TMP_CFG="$(mktemp -d)"
trap 'rm -rf "${TMP_CFG}"' EXIT

cp -a RELEASE "${TMP_CFG}/RELEASE" 2>/dev/null || true
cp -a RELEASE.prev "${TMP_CFG}/RELEASE.prev" 2>/dev/null || true
cp -a compose.yml "${TMP_CFG}/compose.yml" 2>/dev/null || true
cp -a ENV_NAME "${TMP_CFG}/ENV_NAME" 2>/dev/null || true
mkdir -p "${TMP_CFG}/proxy"
cp -a proxy/Caddyfile "${TMP_CFG}/proxy/" 2>/dev/null || true

# Redact .env values but keep keys for restore planning
if [[ -f .env ]]; then
  sed -E 's/^( *[A-Za-z_][A-Za-z0-9_]*=).*/\1***REDACTED***/' .env >"${TMP_CFG}/env.keys-redacted"
fi

tar -C "${TMP_CFG}" -czf "${CONFIG_TGZ}" .
log "config snapshot → ${CONFIG_TGZ}"

{
  echo "time_utc=${TS}"
  echo "host=$(hostname 2>/dev/null || echo unknown)"
  echo "pg_file=${PG_FILE}"
  echo "pg_bytes=${PG_BYTES}"
  echo "minio_dir=${MINIO_DIR:-none}"
  echo "config_tgz=${CONFIG_TGZ}"
  echo "IMAGE_API=${IMAGE_API:-}"
  echo "IMAGE_MS=${IMAGE_MS:-}"
  if [[ -f RELEASE ]]; then
    # shellcheck disable=SC1091
    set -a
    # shellcheck disable=SC1091
    . ./RELEASE
    set +a
    echo "RELEASE_IMAGE_API=${IMAGE_API:-}"
    echo "RELEASE_IMAGE_MS=${IMAGE_MS:-}"
  fi
  echo "git_bundle=$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo n/a)"
} >"${META_FILE}"
log "meta → ${META_FILE}"

# --- Retention ---
if [[ "${RETAIN_DAYS}" =~ ^[0-9]+$ ]] && [[ "${RETAIN_DAYS}" -gt 0 ]]; then
  log "pruning backups older than ${RETAIN_DAYS} days under ${BACKUP_ROOT}"
  find "${BACKUP_ROOT}" -maxdepth 1 -type f -name 'pg-*.sql.gz' -mtime "+${RETAIN_DAYS}" -print -delete || true
  find "${BACKUP_ROOT}" -maxdepth 1 -type f -name 'meta-*.txt' -mtime "+${RETAIN_DAYS}" -print -delete || true
  find "${BACKUP_ROOT}" -maxdepth 1 -type f -name 'config-*.tgz' -mtime "+${RETAIN_DAYS}" -print -delete || true
  find "${BACKUP_ROOT}" -maxdepth 1 -type d -name 'minio-*' -mtime "+${RETAIN_DAYS}" -print -exec rm -rf {} + 2>/dev/null || true
fi

log "backup complete"
ls -lah "${PG_FILE}" "${META_FILE}" "${CONFIG_TGZ}" 2>/dev/null || true
[[ -n "${MINIO_DIR}" && -d "${MINIO_DIR}" ]] && du -sh "${MINIO_DIR}" || true

warn "Copy ${BACKUP_ROOT} off-box periodically (rsync/USB/second host). Local-only backups are not disaster recovery."
