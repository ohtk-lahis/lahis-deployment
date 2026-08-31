# Ask AI — delta for the current AI suggestion path

Audience: a partner who already receives `report.submitted`, pulls incident data, and writes a staff comment. LAHIS does not call the partner model.

Date: 2026-08-31. Staging host: `https://demo.api.lahis.ohtk.org`. Full contract: `INTEGRATION_GUIDELINE.md`.

## Outline

1. Reuse the current suggestion stack.
2. Subscribe a second event. Do not reuse `report.submitted`.
3. Follow the officer click → webhook → pull → comment path.
4. Read the new webhook fields, including optional `userPrompt`.
5. Write the summary comment with `metadata.kind=summary`.
6. Confirm the partner checklist before go-live.

## 1. Reuse

Keep HMAC, OAuth client-credentials, thin webhook bodies, incident GET, image GET, and comment POST. Keep staff-only comments. Keep the same tenant host.

## 2. What is new

| Item | Change |
| --- | --- |
| Trigger | Officer clicks **Ask AI** on report or case detail. Not automatic on submit. |
| Event | `ai.evaluation_requested`. Add this event type on the webhook endpoint. |
| Repeat | Many requests per report. LAHIS rejects a second click for 60 seconds (`already_in_flight`). |
| Extra instruction | Optional officer text. Field `userPrompt`. Max 2000 characters. Omit when empty. |
| Pull extras | GET comments. Incident detail adds `rendererData`, `followUps`, `village` when the client has `ai:read_report`. |
| Write | Same comment POST. Set `metadata.kind` to `summary`. |

## 3. Runtime

1. Officer opens Extra instruction, then Send. GraphQL returns at once.
2. LAHIS HMAC-POSTs `ai.evaluation_requested` to the webhook.
3. Partner verifies the signature, returns HTTP 2xx, then runs the model.
4. Partner GETs incident, comments, and images (if vision is approved).
5. Partner POSTs a staff comment. The officer reads the comment in Comments.

An endpoint that lists only `report.submitted` does not receive Ask AI clicks.

HMAC is unchanged: `POST + "\n" + path + "\n" + timestamp + "\n" + raw body`.

## 4. Event body (delta)

```json
{
  "schemaVersion": "2026-08-31",
  "eventType": "ai.evaluation_requested",
  "eventId": "{uuid}",
  "purpose": "summary",
  "userPrompt": "Focus on clinical signs.",
  "requestedBy": {"username": "L01", "role": "ADM"},
  "report": {"id": "{reportId}"},
  "links": { "incident": "…", "comments": "…", "images": "…" }
}
```

Do not treat a missing field as `""`. If `userPrompt` is absent, run the default summarize task.

## 5. Write-back

Use idempotency key `ai-summary:{eventId}`.

```json
{
  "externalActionId": "ai-summary-{eventId}",
  "body": "AI summary:\n…",
  "visibility": "staff",
  "metadata": {
    "kind": "summary",
    "requestedEventId": "{eventId}"
  }
}
```

`kind=summary` does not overwrite Excel suspected-disease. Missing `kind` copies the body into `ai_suspected` (current suggestion behaviour).

## 6. Partner checklist

- Webhook event types include `ai.evaluation_requested`.
- Client scopes: `ai:read_report`, `incident:read`, `ai:create_comment`, plus `ai:read_images` if vision is approved.
- If `userPrompt` is present, add that text on top of the default summarize task.
- POST comment with `metadata.kind=summary`.
- Do not call GraphQL. Do not scrape dashboard media URLs.

Tenant must also set `integrations.ai_enabled=enable` and an AI Comment Owner, or staff will not see the button or the comment.
