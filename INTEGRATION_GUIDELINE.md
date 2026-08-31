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
   Subscribe only to the events the partner will handle. `report.submitted` and
   `ai.evaluation_requested` are separate subscriptions.
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
| Extra incident text for AI summary | `incident:read` and `ai:read_report` | `GET /incidents/{reportId}` (detail only) |
| Read census snapshots | `census:read` | `GET /census/snapshots` |
| Read latest census | `census:read` | `GET /census/latest` |
| List report images | `ai:read_images` | `GET /reports/{reportId}/images` |
| Download report image bytes | `ai:read_images` | `GET /reports/{reportId}/images/{imageId}/content` |
| Read report thread comments | `ai:read_report` | `GET /reports/{reportId}/comments` |
| Create integration comment | `ai:create_comment` | `POST /reports/{reportId}/comments` |
| Create/update risk assessment | `risk:update` | `POST /reports/{reportId}/risk-assessments` |
| Create/read cluster result | `cluster:write_result` | `POST /clusters`, `GET /clusters/{clusterId}` |

Additional configured scopes are `cluster:read_inputs`, `ai:read_report`, and
`case:promote`; agree their use with the LAHIS technical owner before relying
on them. `report.submitted` and `ai.evaluation_requested` webhook delivery
require `ai:read_report` on the client in addition to an active endpoint
subscribed to that event type. Image list/download requires `ai:read_images`
and is granted only to approved AI clients.

Incident **list** stays thin for every client. Incident **detail** stays thin
when the client has only `incident:read`. When the same client also has
`ai:read_report`, detail adds `village`, `rendererData`, and `followUps`
(staff-visible rendered text). It still does not expose raw form JSON,
reporter identity, or image bytes.

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

An AI feedback client needs `ai:read_report` to receive outbound AI webhooks
and `ai:create_comment` to write staff feedback. Add `incident:read` when the
AI service must re-read the incident through REST. Add `ai:read_images` only
when the service is approved to pull report photos for vision analysis.

Two outbound events exist. Subscribe the webhook endpoint to each event the
partner will handle:

| Event | When LAHIS sends it |
| --- | --- |
| `report.submitted` | A report is stored. Automatic. One active event per report. |
| `ai.evaluation_requested` | An officer clicks **Ask AI to summarize** on report or case detail. Optional `userPrompt`. Many requests per report are allowed, with a 60-second debounce. |

The dashboard button is shown only when tenant configuration
`integrations.ai_enabled` is `enable`. Reporters never see the button.
Missing that key hides the button.

The `report.submitted` event and the default incident-read body are
intentionally thin. They expose report and tenant identifiers, timestamps,
report type/category, authority IDs, case ID, optional location, current risk
projection, and integration links. They do **not** expose raw form data,
reporter identity, uploaded non-image files, or permanent public media URLs
through this integration contract. Image **bytes** are available only through
the dedicated image endpoints below when the client holds `ai:read_images`.
Officer-requested summaries also pull rendered report text, follow-ups, and
thread comments as described below.

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
    "riskAssessments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/risk-assessments",
    "images": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/images"
  }
}
```

### Officer-requested summary (`ai.evaluation_requested`)

An officer on the dashboard can request a summary of one report. LAHIS does
not call the partner model. The dashboard queues this event. The partner pulls
inputs, then writes a staff comment.

Required client scopes for this path:

- `ai:read_report` (webhook delivery and GET comments)
- `incident:read` (incident detail)
- `ai:read_images` (photos, when vision is approved)
- `ai:create_comment` (write the summary)

The webhook endpoint must include `ai.evaluation_requested` in its event
types. An endpoint that only lists `report.submitted` will not receive officer
clicks.

Example webhook body (illustrative IDs only). `userPrompt` is omitted when the
officer left the extra-instruction box empty. Do not treat an empty string as
a prompt.

```json
{
  "schemaVersion": "2026-08-31",
  "eventType": "ai.evaluation_requested",
  "eventId": "44444444-4444-4444-4444-444444444444",
  "producedAt": "2026-08-31T10:30:00+00:00",
  "purpose": "summary",
  "userPrompt": "Focus on clinical signs and deaths in the last 7 days.",
  "tenant": {"schema": "demo", "code": "demo", "name": "LAHIS Demo"},
  "requestedBy": {"id": "10", "username": "L01", "role": "ADM"},
  "report": {
    "id": "22222222-2222-2222-2222-222222222222",
    "createdAt": "2026-08-31T10:29:58+00:00",
    "incidentDate": "2026-08-31",
    "reportType": {"id": "33333333-3333-3333-3333-333333333333", "name": "Animal Sick/Death", "category": "Animal"},
    "relevantAuthorityIds": [12],
    "caseId": null
  },
  "links": {
    "incident": "/api/integrations/v1/incidents/22222222-2222-2222-2222-222222222222",
    "comments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/comments",
    "riskAssessments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/risk-assessments",
    "images": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/images"
  }
}
```

`purpose` is `summary` for this dashboard action. `requestedBy` is the officer
who clicked. The webhook body still does not include form answers, renderer
text, images, or comment text. Those are pulled through REST.

Recommended partner flow:

1. Verify HMAC as for `report.submitted`.
2. Accept `eventType=ai.evaluation_requested` and `purpose=summary`.
3. If `userPrompt` is present, use it as extra officer instruction on top of
   the default summarize task. If it is absent, run the default summarize
   task.
4. `GET .../incidents/{reportId}` with `incident:read` and `ai:read_report` to
   receive `rendererData`, `followUps`, and `village`.
5. `GET .../reports/{reportId}/images` and image content when vision is
   approved.
6. `GET .../reports/{reportId}/comments` for the staff thread.
7. `POST .../reports/{reportId}/comments` with `metadata.kind` = `summary` and
   idempotency key `ai-summary:{eventId}`.
8. Return HTTP 2xx on the webhook quickly; run the model after ack.

Incident detail extra fields when the client has `ai:read_report` (in addition
to the thin incident summary):

```json
{
  "village": {"id": 10, "code": "V-1", "name": "Sangthong", "authorityId": 12},
  "rendererData": "staff-visible rendered report text",
  "followUps": [
    {
      "id": "55555555-5555-5555-5555-555555555555",
      "createdAt": "2026-08-31T11:00:00+00:00",
      "rendererData": "rendered follow-up text"
    }
  ]
}
```

List incidents never includes those extra fields.

### Read thread comments

```text
GET ${TENANT_API_URL}/api/integrations/v1/reports/{reportId}/comments
Authorization: Bearer <access-token>
```

No idempotency key is required. Oldest comments first. An empty thread returns
`"comments": []`. Example:

```json
{
  "schemaVersion": "2026-08-31",
  "reportId": "22222222-2222-2222-2222-222222222222",
  "comments": [
    {
      "id": "1",
      "body": "Officer note.",
      "createdAt": "2026-08-31T10:40:00+00:00",
      "authorUsername": "V01",
      "isAiOwner": false,
      "attachments": [
        {"id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "fileName": "lab.pdf", "kind": "document"}
      ]
    }
  ]
}
```

`isAiOwner` is true when the comment author is the tenant **AI Comment Owner**.
Attachment **bytes** are not returned on this path. A missing report returns
`404 incident_not_found`.

### Pull report images (optional vision path)

Recommended partner flow when vision is approved:

1. Receive `report.submitted` or `ai.evaluation_requested` (thin body; use `links.images` or the report ID).
2. `GET .../reports/{reportId}/images` for metadata.
3. For each needed image, `GET .../images/{imageId}/content` with the same
   bearer token.
4. Run analysis on the partner side.
5. `POST .../reports/{reportId}/comments` with decision-support text only.

Use the report ID from the event. Do **not** scrape dashboard media hosts or
guess public object URLs; the sanctioned path is the integration API with a
service token. Dashboard/MinIO public media URLs (when present in an
environment) are **not** part of the integration contract.

```text
GET ${TENANT_API_URL}/api/integrations/v1/reports/{reportId}/images
Authorization: Bearer <access-token>
```

Example list response (illustrative):

```json
{
  "schemaVersion": "2026-06-02",
  "reportId": "22222222-2222-2222-2222-222222222222",
  "images": [
    {
      "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      "isCover": true,
      "contentType": "image/jpeg",
      "byteSize": 245678,
      "createdAt": "2026-07-21T10:29:59+00:00",
      "links": {
        "content": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/images/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/content"
      }
    }
  ],
  "links": {
    "incident": "/api/integrations/v1/incidents/22222222-2222-2222-2222-222222222222",
    "comments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/comments"
  }
}
```

A report with no photos returns `200` and `"images": []`. Soft-deleted images
are omitted. Cover image (if set) is listed first, then remaining images by
creation time. Metadata includes `id`, `isCover`, `contentType`, `byteSize`,
`createdAt`, and a relative `links.content` path. Permanent public media URLs
are not returned. List and content access are audited under action types
`ai.read_images` and `ai.read_image_content`.

```text
GET ${TENANT_API_URL}/api/integrations/v1/reports/{reportId}/images/{imageId}/content
Authorization: Bearer <access-token>
```

Successful content responses stream the **stored file bytes as-is** with
`Cache-Control: private, no-store`. Content-Type is taken from the uploaded
file or guessed from the filename (fallback `application/octet-stream`). The
image must belong to the given report; cross-report IDs return
`404 image_not_found`.

**Privacy.** Image content may retain embedded EXIF (including GPS) and may
depict people or surroundings. Partners must treat photos as sensitive,
minimize retention, delete local copies when analysis is finished, and must
not use them for model training unless the LAHIS technical owner and partner
agreement explicitly allow it. Soft-delete or missing storage files stop
listing and download; partners must not cache content indefinitely as a
substitute for LAHIS retention control.

| Status | Code | When |
| --- | --- | --- |
| 200 | — | List metadata or content bytes OK |
| 401 | `oauth_required` | Missing/invalid bearer token |
| 403 | `scope_denied` | Client lacks `ai:read_images` |
| 403 | `service_identity_denied` | Human-bound OAuth token |
| 403 | feature / tenant codes | Integrations or AI feature disabled; wrong schema |
| 404 | `incident_not_found` | Report not in this tenant |
| 404 | `image_not_found` | Image missing, soft-deleted, wrong report, or file gone |

Enablement gate: grant `ai:read_images` only after product/security approval for
that partner and tenant. Disable or revoke the client to cut off access.
`ai:read_images` is independent of `incident:read`; vision clients still need
`ai:read_report` for webhooks and `ai:create_comment` to write feedback.

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

Officer-requested **summary** (from `ai.evaluation_requested`) must set
`metadata.kind` to `summary` so LAHIS does not copy the body onto Excel
`ai_suspected`:

```json
{
  "externalActionId": "ai-summary-44444444-4444-4444-4444-444444444444",
  "body": "AI summary:\nTwo pigs died. Clinical signs match the officer prompt.",
  "visibility": "staff",
  "metadata": {
    "kind": "summary",
    "requestedEventId": "44444444-4444-4444-4444-444444444444",
    "model": "partner-model-v1"
  }
}
```

Use idempotency key `ai-summary:{eventId}` so webhook retries do not create a
second thread comment.

`body` (or the equivalent `comment`) is required and `visibility` currently
supports only `staff`. The response is `202` with an integration-owned comment
ID, report ID, external action ID, creation time, and whether a recommendation
was stored. A repeated identical action returns `202` with `status: replayed`.

`metadata.kind` controls Excel suspected-disease:

| `metadata.kind` | Effect on `IncidentReport.ai_suspected` |
| --- | --- |
| missing, `suspected`, or `assessment` | Copy comment body (existing AI feedback). |
| `summary` | Do not copy. Thread comment is still created when AI Comment Owner is set. |

If the tenant **AI Comment Owner** is empty, the integration comment is stored
but the dashboard Comments widget stays empty. Set that owner in
**Admin → Integrations → Settings** before go-live.

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
  },
  "links": {
    "comments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/comments",
    "riskAssessments": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/risk-assessments",
    "images": "/api/integrations/v1/reports/22222222-2222-2222-2222-222222222222/images"
  }
}
```

The incident **list** body stays thin: no image array, form data, or media
URLs. The `links.images` path still requires `ai:read_images` to call. An AI
client that also has `ai:read_report` receives extra summary fields on
**detail only** (`village`, `rendererData`, `followUps`); cluster clients
that hold only `incident:read` do not.

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

Current outbound events are `report.submitted` (new report stored) and
`ai.evaluation_requested` (officer asked for an AI summary). Each JSON body
includes `schemaVersion`, `eventType`, `eventId`, `producedAt`, tenant
metadata, a report summary, and relative links to authorized integration
resources. `ai.evaluation_requested` also includes `purpose` (`summary`),
`requestedBy`, and optional `userPrompt`. Fetch fuller data only with the
OAuth scope that was approved.

HMAC verification is the same for both events. Deduplicate by
`X-OHTK-Event-ID`. Officer summary requests are **not** unique per report;
each click has a new `eventId`.

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
client (including `ai:read_images`), endpoint, signing secret, and
`test_flag=true` report with a synthetic image; then verifies:

- one signed `report.submitted` delivery through Celery;
- OAuth client-credentials authentication and tenant routing;
- incident and census reads (incident stays thin; `links.images` present);
- report image list and authenticated image content download;
- comment, risk-assessment, and cluster writes;
- idempotency replay for comment and cluster writes; and
- cleanup by disabling the temporary endpoint/client and removing its runtime
  secret.

It proves the first delivery attempt, not scheduled retry behaviour, stale
`DELIVERING` recovery, or a production secret-manager implementation. Image
steps require an API image that includes the `ai:read_images` endpoints. The
generated records remain labelled `integration-smoke-...` as staging evidence.
The current smoke still covers `report.submitted` only; officer
`ai.evaluation_requested` is verified with a subscribed endpoint and a
dashboard click (or an equivalent staff mutation) on a `test_flag=true`
report.

Use `SMOKE_KEEP_ENDPOINT=1` only for an approved debugging session and disable
that retained client/endpoint when finished.

## Go-live checklist

- [ ] Parameters, tenant, partner owner, and support contact approved.
- [ ] Minimum scopes and event types approved (include `ai:read_images` only
      when vision is approved for that partner/tenant; include
      `ai.evaluation_requested` only when officer Ask-AI is in scope).
- [ ] If officer Ask-AI is in scope: tenant `integrations.ai_enabled` is
      `enable`, webhook subscribed to `ai.evaluation_requested`, AI Comment
      Owner set, and partner writes `metadata.kind=summary`.
- [ ] If images are in scope: partner retention, no-training (unless agreed),
      and EXIF/sensitive-photo handling are documented in the partner agreement.
- [ ] Client secret and webhook signing secret transferred/stored securely.
- [ ] Callback URL is HTTPS and receiver verifies signature, timestamp, tenant,
      integration code, and event-ID deduplication.
- [ ] Partner write paths send an idempotency key and handle `202` replay and
      conflict responses safely.
- [ ] Partner does not scrape public media hosts; image access uses integration
      REST only when scoped.
- [ ] Synthetic staging smoke passes with no retained temporary credentials.
- [ ] Permanent endpoint/client have an owner, rotation date, timeout, and
      disable/incident procedure.
- [ ] No production data is used until the staging evidence is accepted.
