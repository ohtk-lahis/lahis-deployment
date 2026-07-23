# LAHIS staging deployment handoff

Use this runbook to deploy the dashboard and API on the LAHIS staging host.
It is for the delegated operator; it does **not** authorize database resets,
secret rotation, DNS changes, or a production deployment.

## Release parameters

Fill these values in the release ticket before handing the runbook to an
operator. Keep the names unchanged so the deployment, mobile, and tester
documents refer to the same target.

| Parameter | Meaning | Current staging example |
| --- | --- | --- |
| `DASHBOARD_URL` | Public dashboard base URL, no trailing slash | `https://lahis.ohtk.org` |
| `API_URL` | Public parent API base URL, no trailing slash | `https://api.lahis.ohtk.org` |
| `SERVER_LIST_ENDPOINT` | Mobile tenant/server-list endpoint | `https://api.lahis.ohtk.org/api/servers/` |
| `DEMO_TENANT` | Demo tenant schema/slug | `demo` |
| `DEMO_TENANT_GRAPHQL_URL` | Demo tenant GraphQL endpoint | `https://demo.api.lahis.ohtk.org/graphql/` |

For a new domain, change the parameter values and the host `.env`/tenant-domain
configuration together. Do not silently retain an old server-list endpoint in
the mobile build.

For the parameterized commands below, export the approved values in the
operator shell before use:

```bash
export DASHBOARD_URL='<DASHBOARD_URL>'
export API_URL='<API_URL>'
export SERVER_LIST_ENDPOINT='<SERVER_LIST_ENDPOINT>'
export DEMO_TENANT='<DEMO_TENANT>'
export DEMO_TENANT_GRAPHQL_URL='<DEMO_TENANT_GRAPHQL_URL>'
```

## Scope and ownership

| Area | Delegated operator may do | Requires product/technical owner approval |
| --- | --- | --- |
| API and dashboard images | Deploy the two approved, immutable image digests | Selecting the release and its migration status |
| Database schema | Review the migration plan | Applying a migration |
| Demo seed data | Nothing by default | Applying or reapplying demo seeds |
| Media | Run the public-media verification | Changing public/private media policy or bucket settings |
| Rollback | Roll back to the previous image pin after a failed deploy | Any data restore or manual database repair |
| Secrets and infrastructure | Verify files exist and permissions are safe | Viewing, changing, copying, or rotating secrets; DNS/TLS/firewall changes |

The operator should record the release request, UTC start/end time, image
digests, migration decision, smoke result, and rollback outcome in the release
ticket. Do not paste `.env` contents, tokens, database connection strings, or
private media URLs into that ticket.

## Inputs required before starting

- Approved API and dashboard **digest** references (not `:latest`).
- A release owner’s explicit answer: **does this API release require a schema
  migration?**
- SSH access to the staging host and access to the image registries.
- Confirmation that the target is staging and the host bundle is
  `/opt/lahis`.
- For a first deployment or a media configuration change: the approved media
  mode. Current staging uses direct public report-media URLs.

Do not continue if any item is missing. In particular, never guess an image
tag, edit `.env`, or apply a migration because a plan appears harmless.

## Normal release procedure

1. Connect and establish the target. This output must identify `staging`.

   ```bash
   ssh lahis
   cd /opt/lahis
   cat ENV_NAME
   git status --short
   docker compose ps
   ```

   Stop and escalate if `ENV_NAME` is not `staging`, the deployment bundle has
   unexpected edits, or a prerequisite service is unhealthy.

2. Preserve the current state in the release ticket without exposing secrets.

   ```bash
   sed -n '1,20p' RELEASE
   docker compose ps
   ```

   Record only the `IMAGE_API` and `IMAGE_MS` values. Do not include any `.env`
   values in the ticket.

3. If the release owner approved a database migration, review it first.

   ```bash
   docker compose up -d db redis
   ./scripts/migrate.sh --plan
   ```

   Send the plan to the release owner. Apply only after a second explicit
   approval:

   ```bash
   ./scripts/migrate.sh
   ```

   `migrate.sh` changes the database. It has a five-second cancellation window
   and runs shared-schema migration before tenant-schema migration. A normal
   image deploy never runs it automatically.

4. Deploy both approved images together. The command snapshots the old pin in
   `RELEASE.prev`, pulls images, recreates `api`, `celery`, and `ms`, and
   automatically restores the previous pins if its health check fails.

   ```bash
   ./scripts/deploy.sh \
     --api 'APPROVED_API_IMAGE@sha256:...' \
     --ms 'APPROVED_DASHBOARD_IMAGE@sha256:...'
   ```

   Do not use `ALLOW_LATEST=1`, `NO_ROLLBACK=1`, or a hand-edited `RELEASE`
   file for staging releases.

5. Run the strict post-deploy gate. It verifies every service, the public API,
   dashboard, tenant GraphQL endpoint, and the public-media sentinel.

   ```bash
   SMOKE_STRICT=1 ./scripts/smoke.sh
   ```

   A successful result has `fail=0`. For direct public media, it must also show
   both `PASS public media URL configuration` and
   `PASS public public media sentinel (HTTP 200)`. Treat either media failure
   as a release failure: uploads may appear successful while submitted images
   are broken to users.

6. Perform the short functional check in a browser:

   - `${DASHBOARD_URL}/` loads.
   - `${DASHBOARD_URL}/privacy-policy` loads without sign-in.
   - `${API_URL}/health` returns `ok`.
   - `${SERVER_LIST_ENDPOINT}` responds.
   - `${DEMO_TENANT_GRAPHQL_URL}` accepts `query { __typename }`.

   Record pass/fail, not credentials or response bodies containing user data.

## Demo seeds: separate, approval-only operation

The seed script is deliberately excluded from the normal deploy path. It
upserts FAO/demo configuration, forms, capabilities, and demo reference data
in the `${DEMO_TENANT}` tenant. It can change visible staging behaviour.

Run it only with a written request that identifies the seed bundle and tenant:

```bash
cd /opt/lahis
TENANT_SCHEMA="${DEMO_TENANT}" ./scripts/apply-demo-seeds.sh
SMOKE_STRICT=1 ./scripts/smoke.sh
```

Never use this command against an unnamed tenant or a production-like tenant.

## Recovery

If `deploy.sh` reports that automatic rollback succeeded, do not retry. Attach
the deployment log excerpt without secrets and escalate to the release owner.

For an approved manual image rollback:

```bash
cd /opt/lahis
./scripts/rollback.sh
SMOKE_STRICT=1 ./scripts/smoke.sh
```

`rollback.sh` restores the preceding image pins only; it does not reverse a
database migration, delete media, or repair data. Database restore requires a
separate, explicitly approved incident procedure.

## Non-negotiable safety rules

- Never run `docker compose down -v` or delete `/data/pg`, `/data/redis`,
  `/data/minio`, or `/data/backups`.
- Never run `restore-pg.sh` or `restore-minio.sh` during a release.
- Never expose MinIO console, Postgres, Redis, `.env`, signing keys, or API
  secrets.
- Keep `RUN_MIGRATIONS=0` for long-running API and Celery services.
- Use digest-pinned images only. The release scripts intentionally reject
  floating `latest` tags.
- Do not fix a failed strict smoke by weakening it with `SKIP_PUBLIC=1`.

## Handoff acceptance

The delegated operator hands back:

- API and dashboard digest values deployed;
- migration plan result and the approval reference, or `no migration`;
- strict smoke summary with `fail=0`;
- browser functional-check result;
- whether demo seeds were applied; and
- whether a rollback occurred.

The release is not accepted until the technical owner acknowledges this record.
