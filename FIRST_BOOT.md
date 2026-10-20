# How to install a LAHIS server

Install the one-machine Docker Compose stack on a **new Ubuntu 22.04/24.04 LTS
host with an empty database**. This covers the API, dashboard, Celery worker,
Celery Beat, PostgreSQL/PostGIS, Redis, MinIO, and Caddy.

Reviewed against deployment source on **2026-10-20**. This review checks the
procedure against the scripts and application code; it does not certify a new
installation on a live host. Record the host-specific results at the end.

For updates to an existing server, use [STAGING_DEPLOY_HANDOFF.md](./STAGING_DEPLOY_HANDOFF.md).
For restoring data, use [the restore procedures](./scripts/README.md).
Do not use this fresh-install path to reset an existing database.

This is an operator procedure. Stop at any failed gate. Never run
`docker compose down -v` or delete `/data/*` to recover from an installation error.

## 1. Prepare the host and deployment bundle

Before starting, obtain:

- An approved checkout or deployment bundle from `ohtk-lahis/lahis-deployment`;
  record its commit in the installation notes.
- SSH/sudo access to the intended host and an existing deployment user.
- Approved API and `lahis-ms` image **digests** that support the host architecture,
  plus registry read access. The API image must include the Daphne entrypoint,
  gated migrations, MinIO settings, and both Celery entrypoints.
- DNS control for the dashboard, API parent, demo tenant, and media host.
- Unique Django, database, MinIO root, and MinIO application secrets.
- Firewall rules allowing public TCP 80/443 and restricted SSH. PostgreSQL and
  Redis stay private; the MinIO console binds only to host loopback.

On the target host, from the approved bundle directory:

```bash
# Replace ubuntu with the existing deployment user on this host.
sudo DEPLOY_USER=ubuntu ./scripts/bootstrap-host.sh
```

The script installs Docker Engine and the Compose plugin, copies the bundle to
`/opt/lahis`, creates `/data` directories, and seeds `.env`, `RELEASE`, and the
`ENV_NAME` marker. It does **not** start services or apply migrations. It leaves
firewall configuration unchanged unless `CONFIGURE_UFW=1` is explicitly supplied;
also check any cloud firewall. Reconnect as the deployment user after Docker group
membership changes.

```bash
cd /opt/lahis
```

Use this directory and the same Bash session for the following commands.
Defaults below use the staging names in [CONTRACT.md](./CONTRACT.md).

## 2. Set environment, release images, DNS, and TLS

Edit `.env` using [.env.example](./.env.example) as the key reference; keep its
permissions at `600`. These files are sourced by the scripts, so use trusted,
shell-compatible assignments and quote special characters in secrets. Do not
print `.env`, share rendered Compose output, or enable shell tracing.

Check these relationships before starting:

| Setting | Required value or relationship |
|---------|--------------------------------|
| `ENV_NAME` / marker file | `staging` for this procedure |
| `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Match `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` respectively |
| `DB_HOST`, `REDIS_HOST` | `db`, `redis` inside Compose |
| `RUN_MIGRATIONS` | `0`; migrations run separately |
| `serverDomain` | API parent hostname, default `api.lahis.ohtk.org` |
| `tenantsApiEndpoint` | `https://api.lahis.ohtk.org/api/servers/` |
| `DASHBOARD_URL` | `https://lahis.ohtk.org` |
| `DJANGO_ALLOWED_HOSTS` | Include API parent and tenant hosts |
| `DEMO_TENANT_HOST` | `demo.api.lahis.ohtk.org` |
| `FCM_DRY_RUN` | `True` unless real push testing is explicitly intended |

Leave optional `DJANGO_SUPERUSER_*` variables unset: create the tenant admin
explicitly in section 8. The default web entrypoint does not select the demo
tenant for that bootstrap user.

Replace **both** `IMAGE_API` and `IMAGE_MS` in `RELEASE` with approved
`registry/repository@sha256:...` references. `RELEASE.example`, `RELEASE.pins`, and
[IMAGE_PINS.md](./IMAGE_PINS.md) contain historical examples, not a current release
selection. Do not deploy their old pins without release review.

Set DNS A/AAAA records to this host for:

- `lahis.ohtk.org`
- `api.lahis.ohtk.org`
- `demo.api.lahis.ohtk.org`
- `minio.lahis.ohtk.org`

Only publish an AAAA record if IPv6 reaches the host. Additional tenants need
their own DNS records or wildcard DNS, plus matching database domain rows.

**Prepare `proxy/Caddyfile` before starting the proxy.** The supplied file has
explicit dashboard, API parent, demo, and MinIO sites, plus a wildcard tenant
site. DNS-01 for wildcard certificates is **not configured** in the supplied
stack. For a first install using the explicit demo host, remove the entire
`*.{$API_HOST:api.lahis.ohtk.org} { ... }` site block from the host's Caddyfile.
Keep the explicit demo block. For each additional tenant, add an explicit site
that proxies to `api:8000`, or provision and validate a wildcard certificate
strategy before enabling the wildcard block. Wildcard DNS alone does not provide
a wildcard certificate.

If using different hostnames, update `.env`, Caddy site names, tenant domains,
dashboard URLs, and media URLs together. `DEMO_TENANT_HOST` does not rewrite the
Caddyfile's literal `demo.` prefix.

## 3. Preflight and pull images

Run in Bash. Compose automatically reads `.env`, but **does not automatically
read `RELEASE`**. Load `.env` first and `RELEASE` second so release digests win.
Repeat this loading step after changing either file or opening a new session.

```bash
set -euo pipefail
test -f .env
test -f RELEASE
test "$(cat ENV_NAME)" = "staging"
if grep -qE 'change-me|REPLACE' .env; then
  echo "Replace placeholder secrets in .env before continuing" >&2
  exit 1
fi

set -a
. ./.env
. ./RELEASE
set +a

test "${ENV_NAME}" = "staging"
test "${RUN_MIGRATIONS}" = "0"
test "${DB_NAME}" = "${POSTGRES_DB}"
test "${DB_USER}" = "${POSTGRES_USER}"
test "${DB_PASSWORD}" = "${POSTGRES_PASSWORD}"
[[ "${IMAGE_API}" =~ @sha256:[[:xdigit:]]{64}$ ]]
[[ "${IMAGE_MS}" =~ @sha256:[[:xdigit:]]{64}$ ]]
docker info >/dev/null
docker compose config >/dev/null
docker compose pull
```

**Gate:** all commands succeed. The placeholder check is only a spot check;
confirm required secrets are nonempty and appropriate for this host. Verify the
selected image platform and registry access before creating containers.

## 4. Start the data services

```bash
docker compose up -d db redis minio
docker compose ps
docker compose exec -T db pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
docker compose exec -T redis redis-cli ping
docker compose exec -T minio curl -sf http://127.0.0.1:9000/minio/health/live
```

**Gate:** all three services are healthy; Redis returns `PONG`. If startup is
still in progress, wait and repeat the checks. Investigate volume permission or
credential errors without wiping data.

## 5. Bootstrap MinIO media storage

This procedure uses the existing **public media bucket** mode. Objects in that
bucket are anonymously downloadable; confirm this mode is intended for the
installation. A private media deployment needs a separate reviewed URL/access
configuration.

Set these values in `.env` before bootstrapping:

```text
USE_S3=True
AWS_S3_ENDPOINT_URL=http://minio:9000
AWS_S3_ADDRESSING_STYLE=path
AWS_S3_USE_SSL=False
MINIO_BUCKET=lahis-media
AWS_STORAGE_BUCKET_NAME=lahis-media
S3_MEDIA_BUCKET_NAME=lahis-media
AWS_ACCESS_KEY_ID=<dedicated-MinIO-app-key>
AWS_SECRET_ACCESS_KEY=<dedicated-MinIO-app-secret>
AWS_S3_CUSTOM_DOMAIN=minio.lahis.ohtk.org/lahis-media
AWS_QUERYSTRING_AUTH=False
MINIO_PUBLIC_READ=1
```

Replace the angle-bracket placeholders; keep app credentials separate from
`MINIO_ROOT_*`. The public custom domain must include the bucket path, without
`https://`. Reload environment and release values as in section 3 if edited.

```bash
./scripts/bootstrap-minio.sh
```

The script creates the bucket, application user/policy, anonymous download policy,
and public-media sentinel. Review warnings; verify application credentials with
a real upload in section 9.

**Gate:** bucket and user/policy setup succeed. The public sentinel is checked
after HTTPS is available.

## 6. Apply database migrations before starting apps

For the **known empty database** in this procedure, inspect the shared-schema
plan first:

```bash
docker compose run --rm --no-deps -e RUN_MIGRATIONS=0 \
  --entrypoint python api manage.py migrate_schemas --shared --plan
```

Review and approve the plan, then apply:

```bash
./scripts/migrate.sh
./scripts/migrate.sh --plan
```

The apply script migrates shared apps first, creating `tenants_client`, then
runs all schemas. A full `./scripts/migrate.sh --plan` **before** shared tables
exist can fail on a fresh database. The shared-only plan above avoids that
bootstrap problem. The final plan should show no pending migrations.

For an **existing database**, stop this fresh-install procedure: take and verify
a backup, review `./scripts/migrate.sh --plan`, and obtain approval before apply.
Do not interpret another migration error as permission to reset the database.

**Gate:** migrations succeed; no pending migrations remain.

## 7. Start applications and HTTPS proxy

```bash
docker compose up -d api celery celery-beat ms
docker compose ps
docker compose logs --tail=100 api
docker compose logs --tail=50 celery celery-beat
docker compose exec -T api python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health').read())"
```

**Gate:** API health returns `ok`; Daphne is serving the API; startup logs show
migrations skipped; worker, dashboard, and the single Beat instance are running.
Do not scale `celery-beat` beyond one replica. Beat schedules tenant case
auto-close; tenant configuration controls the applicable days.

Start the proxy only after the DNS and Caddyfile preparation in section 2:

```bash
docker compose up -d proxy
docker compose logs --tail=80 proxy
curl -fsS -o /dev/null -w '%{http_code}\n' "https://${DASHBOARD_HOST}/"
curl -fsS "https://${API_HOST}/health"
curl -fsS "https://${API_HOST}/api/servers/"
```

Caddy needs working DNS and reachable ports for certificate issuance. Do not
disable certificate verification to pass these checks. An empty server list is
expected until the tenant is created.

**Gate:** HTTPS works for the dashboard and API parent without certificate errors.

## 8. Create the demo tenant and its administrator

For the first empty database, create the tenant and primary domain. Creating a
new `Client` automatically creates and migrates its tenant schema.

```bash
docker compose exec -T api python manage.py shell <<'PY'
import os
from tenants.models import Client, Domain

host = os.environ["DEMO_TENANT_HOST"]
client, created = Client.objects.get_or_create(
    schema_name="demo", defaults={"name": "LAHIS Demo"},
)
domain, _ = Domain.objects.get_or_create(
    domain=host, defaults={"tenant": client, "is_primary": True},
)
if domain.tenant_id != client.pk or not domain.is_primary:
    raise RuntimeError("Existing domain configuration differs; review before changing it")
print("tenant", client.schema_name, "created=", created, "domain=", host)
PY
```

Create the admin **inside `demo`**, using the interactive password prompt:

```bash
docker compose exec api python manage.py tenant_command createsuperuser --schema=demo
```

Running plain `manage.py createsuperuser` does not select the demo tenant.
Use a unique admin password; demo training accounts/seeds are not required for
installation.

```bash
curl -fsS "https://${API_HOST}/api/servers/"
curl -fsS -X POST "https://${DEMO_TENANT_HOST}/graphql/" \
  -H 'content-type: application/json' \
  --data '{"query":"query { __typename }"}'
```

**Gate:** the server list includes the demo domain; tenant GraphQL returns
`data.__typename` without `errors`; dashboard sign-in works after selecting that
server. Use the HTTPS dashboard hostname for browser login.

## 9. Verify installation and back up

```bash
SMOKE_STRICT=1 ./scripts/smoke.sh
```

**Gate:** zero failures and zero skips, including a passing public-media sentinel check.
Do not use `SKIP_PUBLIC=1` for installation acceptance. The script's GraphQL check
checks HTTP status; inspect the JSON response in section 8 as well.

Complete these manual checks:

| Check | Required evidence |
|-------|-------------------|
| Dashboard login | Tenant admin can sign in and open the intended tenant |
| Media write/read | Upload an avatar or report attachment; confirm object in MinIO and accessible returned HTTPS URL |
| Worker | `docker compose exec -T celery celery -A podd_api inspect ping` returns a worker response |
| Beat | One Beat instance running; review its logs for scheduler errors |
| WebSocket, if used | Verify an authenticated connection through the tenant HTTPS host |

Set `BACKUP_ROOT` in `.env` if the deployment user cannot write to the default
`${DATA_ROOT}/backups`; provision appropriate access for that backup directory.
If edited, reload `.env` and then `RELEASE` as in section 3 before continuing.

```bash
./scripts/backup.sh
ls -la "${BACKUP_ROOT:-${DATA_ROOT}/backups}/"
```

Verify the database dump and MinIO mirror, including warnings in backup output.
The script can warn about a failed MinIO mirror and still finish; exit status
alone is not proof that media was backed up. Its config archive redacts `.env`
values, so keep secrets in a separate secure recovery store. Arrange an off-host
copy and a restore drill on a disposable host using the
[restore procedures](./scripts/README.md).

Record the following without secrets:

```text
Date / operator / host:
Deployment bundle commit:
API and dashboard source revisions / approved image digests / platform:
Environment marker / data and backup locations:
DNS and TLS checks (including tenant and media):
Migration result / demo tenant domain:
Strict smoke pass/fail/skip counts:
Tenant login / media upload / worker / Beat results:
Backup files / verified MinIO mirror / off-host copy / restore drill:
Known issues and owner:
```

## Failure reference and later updates

| Symptom | Check |
|---------|-------|
| Image pull fails | Approved registry reference, access, and host architecture |
| API database connection fails | Data service health; matching `DB_*` and `POSTGRES_*` values |
| API uses `runserver` or migrates on every start | Approved API image and `RUN_MIGRATIONS=0` |
| MinIO access denied | Bucket, application credentials/policy, bootstrap warnings |
| Public media fails | Bucket path in custom domain, anonymous-download policy, media DNS/TLS |
| Server list empty | Tenant and primary Domain row in section 8 |
| Tenant host resolves incorrectly | DNS, Caddy site, original Host, database domain row |
| Wildcard certificate fails | Remove unused wildcard block or configure the reviewed certificate strategy |
| Dashboard uses wrong API | Case-sensitive `serverDomain` and `tenantsApiEndpoint` |

After first boot, follow [STAGING_DEPLOY_HANDOFF.md](./STAGING_DEPLOY_HANDOFF.md)
for approved image updates and service selection. `deploy.sh` handles app image
updates and health rollback; database migrations remain separate. Preserve the
exact running API when updating only the dashboard. Schedule backups and keep
off-host recovery evidence current.
