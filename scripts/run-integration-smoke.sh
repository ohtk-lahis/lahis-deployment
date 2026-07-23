#!/usr/bin/env bash
# Run a staging-only, cross-service integration smoke.
#
# It creates a temporary OAuth integration client and signed webhook endpoint,
# submits a marked test incident, validates outbound delivery, then exercises
# the OAuth incident/census/comment/risk/cluster APIs. The client and endpoint
# are disabled at the end; labelled audit artifacts remain as smoke evidence.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

COMPOSE_FILES=(-f compose.yml -f compose.integration-smoke.yml)
RUNTIME_ENV="${ROOT}/.integration-smoke.runtime.env"
RUN_ID="integration-smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$"
KEEP_ENDPOINT="${SMOKE_KEEP_ENDPOINT:-0}"

cleanup() {
  local result=$?
  set +e

  if [[ "${RUNTIME_CREATED:-0}" == "1" && "${KEEP_ENDPOINT}" != "1" ]]; then
    docker compose "${COMPOSE_FILES[@]}" run --rm --no-deps \
      -v "${RUNTIME_ENV}:/run/integration-smoke.env" \
      --entrypoint python api manage.py shell <<'PY' >/dev/null
import os
from django_tenants.utils import tenant_context
from tenants.models import Client
from integrations.models import IntegrationClient, WebhookEndpoint

client = Client.objects.get(schema_name=os.environ["SMOKE_TENANT_SCHEMA"])
with tenant_context(client):
    code = os.environ["SMOKE_INTEGRATION_CODE"]
    integration_client = IntegrationClient.objects.filter(code=code).first()
    if integration_client:
        WebhookEndpoint.objects.filter(integration_client=integration_client).update(
            status=WebhookEndpoint.Status.DISABLED
        )
        integration_client.status = IntegrationClient.Status.DISABLED
        integration_client.save(update_fields=("status", "updated_at"))
PY
  fi

  if [[ "${RUNTIME_CREATED:-0}" == "1" ]]; then
    docker compose "${COMPOSE_FILES[@]}" stop integration-stub >/dev/null 2>&1 || true
    docker compose "${COMPOSE_FILES[@]}" rm -f integration-stub >/dev/null 2>&1 || true
    rm -f "${RUNTIME_ENV}"
    docker compose -f compose.yml up -d --no-deps --force-recreate api celery >/dev/null 2>&1 || true
  fi
  exit "${result}"
}
trap cleanup EXIT

require_env_marker
load_dotenv
load_release RELEASE
export_images
assert_images_safe

RUNTIME_CREATED=0
SMOKE_TENANT_SCHEMA="${SMOKE_TENANT_SCHEMA:-demo}"
SMOKE_TENANT_HOST="${SMOKE_TENANT_HOST:-${DEMO_TENANT_HOST:-demo.api.lahis.ohtk.org}}"
SMOKE_INTEGRATION_CODE="${SMOKE_INTEGRATION_CODE:-${RUN_ID}}"
export SMOKE_TENANT_SCHEMA SMOKE_TENANT_HOST SMOKE_INTEGRATION_CODE

umask 077
python3 - <<'PY' >"${RUNTIME_ENV}"
import secrets
print("INTEGRATION_SMOKE_WEBHOOK_SECRET=" + secrets.token_urlsafe(32))
PY
RUNTIME_CREATED=1
cat >>"${RUNTIME_ENV}" <<EOF
SMOKE_API_BASE_URL=http://api:8000
SMOKE_TENANT_HOST=${SMOKE_TENANT_HOST}
SMOKE_RECEIVER_URL=http://integration-stub.local:8080
SMOKE_RUN_ID=${RUN_ID}
SMOKE_TENANT_SCHEMA=${SMOKE_TENANT_SCHEMA}
SMOKE_INTEGRATION_CODE=${SMOKE_INTEGRATION_CODE}
EOF

log "starting temporary integration receiver and reloading api/celery"
docker compose "${COMPOSE_FILES[@]}" up -d --no-deps --force-recreate api celery integration-stub

HEALTH_URL="https://${API_HOST:-api.lahis.ohtk.org}/health"
curl --fail --silent --show-error --retry 12 --retry-delay 2 --retry-connrefused "${HEALTH_URL}" >/dev/null

log "creating isolated smoke fixture in tenant ${SMOKE_TENANT_SCHEMA}"
docker compose "${COMPOSE_FILES[@]}" run --rm --no-deps \
  -v "${RUNTIME_ENV}:/run/integration-smoke.env" \
  --entrypoint python api manage.py shell <<'PY'
import os
from django.utils import timezone
from django_tenants.utils import tenant_context
from oauth2_provider.generators import generate_client_secret
from oauth2_provider.models import get_application_model
from accounts.models import Authority, AuthorityUser, Village
from integrations.constants import IntegrationEventType, IntegrationScope
from integrations.models import IntegrationClient, WebhookEndpoint
from reports.models import IncidentReport, ReportType
from reports.signals import incident_report_submitted
from tenants.models import Client

runtime_env = "/run/integration-smoke.env"
run_id = os.environ["SMOKE_RUN_ID"]
tenant = Client.objects.get(schema_name=os.environ["SMOKE_TENANT_SCHEMA"])

with tenant_context(tenant):
    report_type = ReportType.objects.filter(published=True).order_by("ordering", "id").first()
    reporter = AuthorityUser.objects.filter(authority__isnull=False).order_by("id").first()
    village = Village.objects.order_by("id").first()
    if not report_type or not reporter or not village:
        raise SystemExit("smoke requires a published report type, authority user, and village")

    application_model = get_application_model()
    client_secret = generate_client_secret()
    application = application_model(
        name=run_id,
        user=None,
        client_type=application_model.CLIENT_CONFIDENTIAL,
        authorization_grant_type=application_model.GRANT_CLIENT_CREDENTIALS,
        client_secret=client_secret,
        hash_client_secret=True,
    )
    application.full_clean()
    application.save()
    integration_client = IntegrationClient(
        name=run_id,
        code=os.environ["SMOKE_INTEGRATION_CODE"],
        integration_type=IntegrationClient.IntegrationType.AI_ASSISTANT,
        oauth_application=application,
        scope_codes=[
            IntegrationScope.AI_READ_REPORT,
            IntegrationScope.INCIDENT_READ,
            IntegrationScope.CENSUS_READ,
            IntegrationScope.AI_CREATE_COMMENT,
            IntegrationScope.RISK_UPDATE,
            IntegrationScope.CLUSTER_WRITE_RESULT,
        ],
    )
    integration_client.full_clean()
    integration_client.save()
    endpoint = WebhookEndpoint(
        integration_client=integration_client,
        name=run_id,
        url="http://integration-stub.local:8080/webhooks/report-submitted",
        event_types=[IntegrationEventType.REPORT_SUBMITTED],
        active_signing_secret_ref="env://INTEGRATION_SMOKE_WEBHOOK_SECRET",
        custom_headers={"X-OHTK-Smoke-Run": run_id},
    )
    endpoint.full_clean()
    endpoint.save()

    report = IncidentReport.objects.create(
        reported_by=reporter,
        report_type=report_type,
        incident_date=timezone.localdate(),
        data={
            "animal_species": "Integration smoke",
            "num_total_animal": 1,
            "num_sick": 1,
            "num_dead": 0,
            "num_household": 1,
            "tz": "UTC",
            "smokeRunId": run_id,
        },
        test_flag=True,
    )
    report.relevant_authorities.add(reporter.authority)
    incident_report_submitted.send(sender=IncidentReport, report=report)

    with open(runtime_env, "a", encoding="utf-8") as output:
        output.write("SMOKE_CLIENT_ID=" + application.client_id + "\n")
        output.write("SMOKE_CLIENT_SECRET=" + client_secret + "\n")
        output.write("SMOKE_REPORT_ID=" + str(report.id) + "\n")
        output.write("SMOKE_VILLAGE_ID=" + str(village.id) + "\n")

print("fixture created", run_id)
PY
log "running OAuth/read/write smoke"
# The fixture writes client credentials to the runtime env file after the
# receiver is started. Do not let `compose run` reconcile/recreate that
# in-memory receiver here, or its already-delivered receipt would be lost.
docker compose "${COMPOSE_FILES[@]}" --profile integration-smoke run --rm --no-deps integration-smoke
log "integration smoke passed: ${RUN_ID}"
