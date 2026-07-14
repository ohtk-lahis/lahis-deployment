#!/usr/bin/env bash
# LAHIS post-boot smoke checks (step 6)
# Run from deploy root (/opt/lahis or repo checkout with .env).
#
# Usage:
#   ./scripts/smoke.sh
#   SMOKE_STRICT=1 ./scripts/smoke.sh    # fail on optional public HTTPS checks
#   SKIP_PUBLIC=1 ./scripts/smoke.sh     # only in-compose checks

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  . ./.env
  set +a
fi

DASHBOARD_HOST="${DASHBOARD_HOST:-lahis.ohtk.org}"
API_HOST="${API_HOST:-api.lahis.ohtk.org}"
DEMO_TENANT_HOST="${DEMO_TENANT_HOST:-demo.api.lahis.ohtk.org}"
MINIO_PUBLIC_HOST="${MINIO_PUBLIC_HOST:-minio.lahis.ohtk.org}"
SKIP_PUBLIC="${SKIP_PUBLIC:-0}"
SMOKE_STRICT="${SMOKE_STRICT:-0}"

pass=0
fail=0
skip=0

ok() { printf 'PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }
skp() { printf 'SKIP  %s\n' "$*"; skip=$((skip + 1)); }

need_compose() {
  docker compose ps >/dev/null 2>&1 || {
    bad "docker compose not available in ${ROOT}"
    return 1
  }
}

echo "=== LAHIS smoke (${ROOT}) ==="

need_compose || true

# --- compose process presence ---
for svc in db redis minio api celery ms proxy; do
  if docker compose ps --status running --services 2>/dev/null | grep -qx "${svc}"; then
    ok "service running: ${svc}"
  else
    # older compose may not support --status
    if docker compose ps 2>/dev/null | grep -E "^${svc}|[[:space:]]${svc}[[:space:]]" | grep -qi 'up\|running'; then
      ok "service running: ${svc}"
    else
      bad "service not running: ${svc}"
    fi
  fi
done

# --- internal data plane ---
if docker compose exec -T db pg_isready -U "${POSTGRES_USER:-lahis}" -d "${POSTGRES_DB:-lahis}" >/dev/null 2>&1; then
  ok "postgres ready"
else
  bad "postgres not ready"
fi

if docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; then
  ok "redis PONG"
else
  bad "redis not responding"
fi

if docker compose exec -T minio curl -sf http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
  ok "minio live"
else
  bad "minio health failed"
fi

# --- api health inside container ---
if docker compose exec -T api python -c \
  "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5); assert r.read()==b'ok'" \
  >/dev/null 2>&1; then
  ok "api /health (in-container)"
else
  bad "api /health (in-container)"
fi

# --- public HTTPS (optional) ---
public_check() {
  local name="$1" url="$2" expect_substr="${3:-}"
  if [[ "${SKIP_PUBLIC}" == "1" ]]; then
    skp "public ${name} (SKIP_PUBLIC=1)"
    return
  fi
  local body code
  body="$(curl -fsS --connect-timeout 5 --max-time 20 "${url}" 2>/dev/null || true)"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 20 "${url}" 2>/dev/null || echo 000)"
  if [[ "${code}" =~ ^[23][0-9][0-9]$ ]]; then
    if [[ -n "${expect_substr}" && "${body}" != *"${expect_substr}"* ]]; then
      if [[ "${SMOKE_STRICT}" == "1" ]]; then
        bad "public ${name} code=${code} missing '${expect_substr}'"
      else
        skp "public ${name} code=${code} body unexpected (non-strict)"
      fi
    else
      ok "public ${name} (HTTP ${code})"
    fi
  else
    if [[ "${SMOKE_STRICT}" == "1" ]]; then
      bad "public ${name} (HTTP ${code}) ${url}"
    else
      skp "public ${name} (HTTP ${code}) — DNS/TLS may not be ready"
    fi
  fi
}

public_check "api /health" "https://${API_HOST}/health" "ok"
public_check "api /api/servers/" "https://${API_HOST}/api/servers/"
public_check "dashboard" "https://${DASHBOARD_HOST}/"
public_check "minio host reachable" "https://${MINIO_PUBLIC_HOST}/minio/health/live"

# GraphQL typename on demo tenant (POST)
if [[ "${SKIP_PUBLIC}" == "1" ]]; then
  skp "graphql demo tenant (SKIP_PUBLIC=1)"
else
  gql_code="$(
    curl -sS -o /tmp/lahis-gql-smoke.json -w '%{http_code}' --connect-timeout 5 --max-time 20 \
      -X POST "https://${DEMO_TENANT_HOST}/graphql/" \
      -H 'content-type: application/json' \
      --data '{"query":"query { __typename }"}' 2>/dev/null || echo 000
  )"
  if [[ "${gql_code}" =~ ^[23][0-9][0-9]$ ]]; then
    ok "graphql ${DEMO_TENANT_HOST} (HTTP ${gql_code})"
  else
    if [[ "${SMOKE_STRICT}" == "1" ]]; then
      bad "graphql ${DEMO_TENANT_HOST} (HTTP ${gql_code})"
    else
      skp "graphql ${DEMO_TENANT_HOST} (HTTP ${gql_code}) — tenant/TLS may be pending"
    fi
  fi
fi

echo "=== summary: pass=${pass} fail=${fail} skip=${skip} ==="
if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
exit 0
