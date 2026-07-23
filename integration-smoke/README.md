# LAHIS integration smoke

This is a staging-only, cross-service smoke for the integrations layer. It is
not part of `compose.yml` and does not run during normal deploys.

For external-partner onboarding, OAuth, webhook verification, and scope rules,
read the [integration guideline](../INTEGRATION_GUIDELINE.md) first.

It starts two small services from the pinned API image, using only Python's
standard library:

- `integration-stub` receives `report.submitted`, verifies the HMAC signature,
  deduplicates event IDs, and exposes a bounded receipt wait endpoint.
- `integration-smoke` obtains an OAuth client-credentials token and checks
  incident/census reads plus comment/risk/cluster writes and idempotency replay.

## Run on staging

```bash
cd /opt/lahis
./scripts/run-integration-smoke.sh
```

The script:

1. creates a mode-`0600` temporary runtime environment file with a random
   webhook secret;
2. recreates only `api` and `celery` so they can resolve the staging-only
   `env://INTEGRATION_SMOKE_WEBHOOK_SECRET` reference;
3. creates a uniquely named integration client, endpoint, and `test_flag=true`
   incident in the chosen tenant (default `demo`);
4. waits once, up to 35 seconds, for Celery's signed webhook delivery;
5. runs the OAuth/read/write checks;
6. disables the endpoint and client, removes the temporary secret file, stops
   the receiver, and recreates `api`/`celery` without the temporary secret.

The generated report, integration comments/risk/cluster results, and audit rows
remain labelled with the unique `integration-smoke-...` run ID as evidence.
They are test data only; the endpoint and client are disabled after the run.

To retain the active endpoint/client for manual debugging, run:

```bash
SMOKE_KEEP_ENDPOINT=1 ./scripts/run-integration-smoke.sh
```

## Coverage boundary

This proves first-attempt signed delivery, Celery handoff, tenant routing,
OAuth service identity, functional scopes, read/write contracts, idempotency,
and audit creation. It does not prove scheduled retries, stale `DELIVERING`
recovery, or a production secret-manager implementation.
