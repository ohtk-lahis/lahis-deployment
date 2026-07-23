# LAHIS external integration guideline

This guide is the handoff contract for an external service that reads LAHIS
surveillance data, receives events, or writes a scoped result back to LAHIS.
It covers the current REST and webhook integration layer; it is not a general
dashboard GraphQL API guide.

## Parameters

Fill these once in the integration ticket. Use the same values in the staging,
mobile, and tester handoffs.

| Parameter | Meaning | Current staging example |
| --- | --- | --- |
| `DASHBOARD_URL` | Dashboard where an administrator manages clients/endpoints | `https://lahis.ohtk.org` |
| `API_URL` | Parent API host; server-list/health only | `https://api.lahis.ohtk.org` |
| `SERVER_LIST_ENDPOINT` | Mobile server-list endpoint | `https://api.lahis.ohtk.org/api/servers/` |
| `DEMO_TENANT` | Tenant schema/slug for this integration test | `demo` |
| `TENANT_HOST` | Public host for the target tenant | `demo.api.lahis.ohtk.org` |
| `TENANT_API_URL` | Public API URL for the target tenant | `https://demo.api.lahis.ohtk.org` |
| `INTEGRATION_CODE` | Stable, unique, non-secret client code | `<partner>-<purpose>-<environment>` |

All OAuth and integration REST calls use `TENANT_API_URL`, not `API_URL`. The
parent API host exists for health and tenant discovery; the integration layer
requires a tenant host.

## Ownership and approval

| Role | Responsibility |
| --- | --- |
| LAHIS technical owner | Approves target tenant, scopes, event types, callback URL, secret reference, and go-live. |
| LAHIS dashboard administrator | Creates/disables the integration client and webhook endpoint; transfers the one-time OAuth secret securely. |
| Partner integration owner | Secures credentials, verifies webhooks, implements retries/idempotency, and supplies support contacts. |
| Release operator | Runs the staging integration smoke only; does not create a permanent partner client without approval. |

Never put client secrets, bearer tokens, webhook signing secrets, or raw report
payloads in a ticket, source repository, chat, or dashboard custom header.

## Onboarding sequence

1. Agree the minimum required scopes and exact use case. Start read-only unless
   a write capability is explicitly approved.
2. The administrator creates an Integration Client in the dashboard under
   **Admin → Integrations → Clients**, using `INTEGRATION_CODE`, a confidential
   OAuth client, and the client-credentials grant. Record the client ID in the
   handoff; transfer the generated client secret once through the approved
   secret channel.
3. If outbound events are required, create a Webhook Endpoint under
   **Admin → Integrations → Webhook endpoints**. It must have an HTTPS callback
   URL, approved event types, a secret *reference* (not the secret itself), a
   timeout, and a bounded retry policy. Custom headers must be non-secret.
4. The partner completes the OAuth, REST, and webhook checks below against the
   target tenant. Use synthetic or `test_flag=true` data for staging.
5. The release operator runs the automated staging smoke. Enable the permanent
   client/endpoint only after the owner reviews the evidence.

Disable the client and its endpoints immediately if a secret is exposed, the
partner is no longer authorized, or the callback becomes unsafe. Revocation or
deletion does not replace incident investigation and credential rotation.

## Principle: authentication and permission

Request a token from the tenant host:

```text
POST ${TENANT_API_URL}/o/token/
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
client_id=<client-id>
client_secret=<client-secret>
```

Use the returned access token on subsequent requests:

```text
Authorization: Bearer <access-token>
Accept: application/json
```

User tokens and public-schema calls are not integration credentials. A client
must be active, confidential, tenant-scoped, and configured for client
credentials before its scopes are accepted.

Authentication answers **who** is calling; scopes answer **what** that caller
may do. Every request is evaluated in the tenant selected by
`TENANT_API_URL`; a token or client that is valid for another tenant does not
grant cross-tenant access. Use a separate client per partner and purpose, give
it the least scopes possible, and disable the client instead of sharing it.

Integration REST endpoints require a service token with no human user bound to
it. A missing/invalid token returns `401 oauth_required`; an inactive client,
wrong tenant, disabled feature, or missing scope is rejected rather than
silently downgraded.

## Shared REST contract

All paths below are relative to `${TENANT_API_URL}` and are versioned under
`/api/integrations/v1/`.

| Capability | Required scope | Method and path |
| --- | --- | --- |
| List/filter incidents | `incident:read` | `GET /incidents` |
| Read one incident | `incident:read` | `GET /incidents/{reportId}` |
| Read census snapshots | `census:read` | `GET /census/snapshots` |
| Read latest census | `census:read` | `GET /census/latest` |
| Create integration comment | `ai:create_comment` | `POST /reports/{reportId}/comments` |
| Create/update risk assessment | `risk:update` | `POST /reports/{reportId}/risk-assessments` |
| Create/read cluster result | `cluster:write_result` | `POST /clusters`, `GET /clusters/{clusterId}` |

Additional configured scopes are `cluster:read_inputs`, `ai:read_report`, and
`case:promote`; agree their use with the LAHIS technical owner before relying
on them. `report.submitted` webhook delivery requires `ai:read_report` on the
client in addition to an active endpoint.

Respect the documented filters and pagination in responses. Incident and
census response bodies carry `schemaVersion`; treat an unknown major contract
change as a compatibility failure rather than silently guessing fields.

## Write operations and idempotency

Every write must include a stable idempotency key, unique for the intended
action and target. Send it in the HTTP header and, where the operation accepts
one, in the external action/assessment/cluster identifier:

```text
Idempotency-Key: <partner-event-or-action-id>
```

Retry the same completed action with the **same** key and identical payload.
LAHIS returns the original accepted result (`202`) for a replay. Reusing a key
for a different payload or target is a conflict; generate a new key only for a
new logical action. Do not turn a timeout into a second write with a new key
until the original action has been reconciled.

Writes create integration audit records. Partner logs should retain its action
ID, LAHIS response status, target ID, and timestamp, but never credentials or
full sensitive payloads.

## AI feedback integration

### Permission and information available

An AI feedback client needs `ai:read_report` to receive `report.submitted`
events and `ai:create_comment` to write staff feedback. Add `incident:read`
only when the AI service must re-read the incident summary through REST.

The event and incident-read API are intentionally thin. They expose report and
tenant identifiers, timestamps, report type/category, authority IDs, case ID,
optional location, current risk projection, and integration links. They do
**not** expose raw form data, reporter identity, images, uploaded files, or
other original report content through this integration contract.

Example `report.submitted` webhook body (illustrative IDs only):

```json
{
  "schemaVersion": "2026-06-02",
  "eventType": "report.submitted",
  "eventId": "11111111-1111-1111-1111-111111111111",
  "producedAt": "2026-07-21T10:30:00+00:00",
  "tenant": {"schema": "demo", "code": "demo", "name": "LAHIS Demo"},
  "report": {
    "id": "22222222-2222-2222-2222-222222222222",
    "createdAt": "2026-07-21T10:29:58+00:00",
    "incidentDate": "2026-07-21",
    "reportType": {"id": "33333333-3333-3333-3333-333333333333", "name": "Animal Sick/Death", "category": "Animal"},
    "relevantAuthorityIds": [12],
    "caseId": null
  },
  "links": {
    "incident": "/api/integrations/v1/incidents/22222222-2222-2222-2222-222222222222",
    "comments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/comments",
    "riskAssessments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/risk-assessments"
  }
}
```

### Submit AI feedback

Submit a staff-visible comment using the report ID from the event or incident
link. The `Idempotency-Key` and `externalActionId` should identify the same
AI action for simple retry/reconciliation.

```text
POST ${TENANT_API_URL}/api/integrations/v1/reports/{reportId}/comments
Authorization: Bearer <access-token>
Idempotency-Key: ai-feedback-<external-action-id>
Content-Type: application/json
```

```json
{
  "externalActionId": "ai-feedback-20260721-0001",
  "body": "Pattern requires officer review. This is decision support, not a diagnosis.",
  "visibility": "staff",
  "metadata": {"model": "partner-model-v1", "confidence": 0.82},
  "recommendation": {"type": "officer_review", "priority": "high"}
}
```

`body` (or the equivalent `comment`) is required and `visibility` currently
supports only `staff`. The response is `202` with an integration-owned comment
ID, report ID, external action ID, creation time, and whether a recommendation
was stored. A repeated identical action returns `202` with `status: replayed`.

## Cluster integration

### Permission and information available

A cluster detector normally receives `incident:read`, `census:read`, and
`cluster:write_result`. It reads incident summaries and census snapshots from
the scoped REST endpoints, then writes the detected cluster. Cluster result
list/detail reads are limited to results created by the same integration client
and also require `cluster:write_result`.

Incident input is limited to the thin summary described above. Animal census
snapshots provide village ID/code/name, snapshot date/status, definition
version, and facts such as row key/label, dimensions, and measures. They do not
include reporter identity or raw census-form submissions.

Example incident summary returned by `GET /api/integrations/v1/incidents/{id}`:

```json
{
  "schemaVersion": "2026-06-02",
  "incident": {
    "id": "22222222-2222-2222-2222-222222222222",
    "incidentDate": "2026-07-21",
    "testFlag": true,
    "reportType": {"id": "33333333-3333-3333-3333-333333333333", "name": "Animal Sick/Death", "category": "Animal"},
    "relevantAuthorityIds": [12],
    "caseId": null,
    "location": {"lon": 101.003, "lat": 13.233},
    "currentRiskAssessment": null
  }
}
```

### Submit a cluster result

```text
POST ${TENANT_API_URL}/api/integrations/v1/clusters
Authorization: Bearer <access-token>
Idempotency-Key: cluster-20260721-0001
Content-Type: application/json
```

```json
{
  "externalClusterId": "cluster-20260721-0001",
  "algorithmVersion": "partner-detector-v1",
  "window": {"from": "2026-07-20", "to": "2026-07-21"},
  "incidentIds": ["22222222-2222-2222-2222-222222222222"],
  "authorityIds": [12],
  "villageIds": [34],
  "geometry": {"type": "Point", "coordinates": [101.003, 13.233]},
  "radiusMeters": 250.0,
  "score": 0.91,
  "riskLevel": "HIGH",
  "explanation": "Synthetic staging cluster for validation.",
  "metadata": {"model": "partner-detector-v1"}
}
```

`externalClusterId`, `algorithmVersion`, and an ISO-date `window` are required.
Referenced incident, authority, and village IDs must belong to the selected
tenant. `score` is 0–1 when supplied; `riskLevel` is `LOW`, `MEDIUM`, `HIGH`,
or `CRITICAL`. A successful write returns `202` and the LAHIS cluster ID; use
that ID with `GET /api/integrations/v1/clusters/{clusterId}`.

## Risk integration

### Permission and information available

A risk evaluator needs `risk:update`; add `incident:read` only if it must read
the LAHIS incident summary before evaluating. The current risk assessment is
included in an incident summary when one exists, so a partner can avoid writing
an unchanged conclusion. The partner does not receive raw report form data,
reporter identity, or media through this API.

### Submit a risk assessment

```text
POST ${TENANT_API_URL}/api/integrations/v1/reports/{reportId}/risk-assessments
Authorization: Bearer <access-token>
Idempotency-Key: risk-20260721-0001
Content-Type: application/json
```

```json
{
  "externalAssessmentId": "risk-20260721-0001",
  "level": "HIGH",
  "score": 0.84,
  "factors": [
    {"key": "mortality_count", "weight": 0.5},
    {"key": "recent_cluster", "weight": 0.34}
  ],
  "evaluatorVersion": "partner-risk-v1",
  "source": "external_risk_evaluator"
}
```

`level` is required and must be `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`.
`score` is optional but, when present, is 0–1; `source` is
`external_risk_evaluator` or `ai`. Each accepted assessment becomes the
current assessment for that report and replaces the prior current projection.
The `202` response includes the stored assessment, whether it is current, and
the number of replaced current assessments. Replaying the same action returns
the same assessment with `status: replayed`.

## Webhook receiver contract

The initial event is `report.submitted`. Its JSON includes `schemaVersion`,
`eventType`, `eventId`, `producedAt`, tenant metadata, a report summary, and
relative links to authorized integration resources. Fetch fuller data only with
the OAuth scope that was approved.

LAHIS sends these headers:

| Header | Use |
| --- | --- |
| `X-OHTK-Event-ID` | Deduplicate event delivery. |
| `X-OHTK-Tenant` | Verify the expected tenant. |
| `X-OHTK-Integration` | Verify the expected client code. |
| `X-OHTK-Timestamp` | Reject stale requests according to the partner’s agreed clock-skew window. |
| `X-OHTK-Signature` | Lower-case HMAC-SHA256 hex signature. |
| `X-OHTK-Signature-Alg` | `HMAC-SHA256`. |
| `X-OHTK-Signing-Key-ID` / `X-OHTK-Signing-Secret-Version` | Identify the active rotation key/version. |

Verify the signature against the **raw, unchanged request body**. The signed
bytes are exactly:

```text
POST + "\n" + <request-path> + "\n" + <X-OHTK-Timestamp> + "\n" + <raw-body>
```

Compute HMAC-SHA256 over those UTF-8 bytes using the resolved signing secret,
then compare in constant time. Do this before parsing or acting on the event.
Persist `X-OHTK-Event-ID` before performing side effects and return a bounded
2xx response for duplicates. A receiver must be able to safely process an
event more than once.

The partner must acknowledge quickly, queue slow work internally, and make its
own processing idempotent. The partner must not rely on delivery order or use
a webhook payload as authorization to access a different tenant.

## Staging verification gate

Before enabling a new integration, run the built-in smoke from the deploy host:

```bash
cd /opt/lahis
SMOKE_TENANT_SCHEMA="${DEMO_TENANT}" \
SMOKE_TENANT_HOST="${TENANT_HOST}" \
./scripts/run-integration-smoke.sh
```

With current staging parameters, `SMOKE_TENANT_SCHEMA=demo` and
`SMOKE_TENANT_HOST=demo.api.lahis.ohtk.org`. The smoke creates a temporary
client, endpoint, signing secret, and `test_flag=true` report; then verifies:

- one signed `report.submitted` delivery through Celery;
- OAuth client-credentials authentication and tenant routing;
- incident and census reads;
- comment, risk-assessment, and cluster writes;
- idempotency replay for comment and cluster writes; and
- cleanup by disabling the temporary endpoint/client and removing its runtime
  secret.

It proves the first delivery attempt, not scheduled retry behaviour, stale
`DELIVERING` recovery, or a production secret-manager implementation. The
generated records remain labelled `integration-smoke-...` as staging evidence.

Use `SMOKE_KEEP_ENDPOINT=1` only for an approved debugging session and disable
that retained client/endpoint when finished.

## Go-live checklist

- [ ] Parameters, tenant, partner owner, and support contact approved.
- [ ] Minimum scopes and event types approved.
- [ ] Client secret and webhook signing secret transferred/stored securely.
- [ ] Callback URL is HTTPS and receiver verifies signature, timestamp, tenant,
      integration code, and event-ID deduplication.
- [ ] Partner write paths send an idempotency key and handle `202` replay and
      conflict responses safely.
- [ ] Synthetic staging smoke passes with no retained temporary credentials.
- [ ] Permanent endpoint/client have an owner, rotation date, timeout, and
      disable/incident procedure.
- [ ] No production data is used until the staging evidence is accepted.
