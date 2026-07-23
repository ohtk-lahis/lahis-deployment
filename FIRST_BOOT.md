# LAHIS first-boot runbook (step 6)

Bring up the **one-machine** stack for the first time on a practice EC2 or bare metal host.

This is an **operator procedure**, not unattended CI. Pause at each gate.  
Never run `docker compose down -v` or delete `/data/*`.

**Prerequisites**

| Item | Done? |
|------|--------|
| [CONTRACT.md](./CONTRACT.md) hostnames agreed | |
| Host bootstrap ([scripts/bootstrap-host.sh](./scripts/bootstrap-host.sh)) completed | |
| `/opt/lahis/.env` secrets filled (not example placeholders) | |
| API image with **step 4+5** entrypoint/MinIO settings built and pinned in `RELEASE` | |
| DNS A/AAAA for `lahis.ohtk.org`, `api.lahis.ohtk.org`, `*.api.lahis.ohtk.org`, `minio.lahis.ohtk.org` → this host | |
| Firewall: 80/443 reachable; Postgres **not** public | |

Default working directory on host:

```bash
cd /opt/lahis
```

Load image pins if present:

```bash
set -a
[ -f RELEASE ] && . ./RELEASE
set +a
export IMAGE_API IMAGE_MS
```

---

## Phase 0 — Preflight (no containers)

```bash
# Identity
test "$(cat ENV_NAME)" = "staging" && echo "env-marker-ok"

# Secrets not left as change-me (spot check)
grep -E 'change-me|REPLACE' .env && echo "FIX SECRETS" && exit 1 || echo "secrets-look-set"

# Compose validates
docker compose config >/dev/null && echo "compose-ok"

# Docker works
docker run --rm hello-world >/dev/null && echo "docker-ok"
```

**Gate 0:** fix any failure before continuing.

---

## Phase 1 — Data plane only

Start database, Redis, MinIO. Do **not** start api/ms/proxy yet.

```bash
docker compose up -d db redis minio
docker compose ps
```

Wait healthy:

```bash
# Postgres
docker compose exec -T db pg_isready -U "${POSTGRES_USER:-lahis}" -d "${POSTGRES_DB:-lahis}"

# Redis
docker compose exec -T redis redis-cli ping

# MinIO
docker compose exec -T minio curl -sf http://127.0.0.1:9000/minio/health/live
```

**Gate 1:** all three healthy. If Postgres volume permission errors, fix ownership once, then retry — do not wipe `/data/pg` without a deliberate restore plan.

---

## Phase 2 — MinIO bucket

```bash
./scripts/bootstrap-minio.sh
```

Confirm `.env` has:

```text
USE_S3=True
AWS_S3_ENDPOINT_URL=http://minio:9000
AWS_S3_ADDRESSING_STYLE=path
AWS_S3_USE_SSL=False
AWS_STORAGE_BUCKET_NAME=lahis-media   # or your MINIO_BUCKET
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_S3_CUSTOM_DOMAIN=minio.lahis.ohtk.org/lahis-media
AWS_QUERYSTRING_AUTH=False
MINIO_PUBLIC_READ=1
RUN_MIGRATIONS=0
```

**Gate 2:** bucket exists, app credentials work, and the public-media sentinel
is created. After TLS/proxy setup, `./scripts/smoke.sh` must report
`PASS public media sentinel`.

---

## Phase 3 — Schema migrations (gated)

Plan first:

```bash
./scripts/migrate.sh --plan
```

Review output. Then apply:

```bash
./scripts/migrate.sh
```

**Gate 3:** migrate finishes without error.  
If this is a **shared** DB with real data, stop and get approval before apply — empty staging DB is the contract default.

---

## Phase 4 — Application processes

```bash
docker compose up -d api celery ms
docker compose ps
docker compose logs -f api --tail=100
# Ctrl-C when you see daphne listening (do not leave -f forever in runbooks)
```

Quick in-network checks (before public proxy):

```bash
# API health (HealthCheckMiddleware)
docker compose exec -T api python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health').read())"

# Or from another container:
docker compose run --rm --no-deps curlimages/curl:8.5.0 -sf http://api:8000/health
```

If the `curl` image line fails (network), use the python check inside `api`.

Expect: `ok` from `/health`.  
Expect logs: ASGI/daphne, **not** long-term reliance on `runserver`.  
Expect logs: **Skipping migrations** (unless you intentionally set `RUN_MIGRATIONS=1`).

**Gate 4:** api healthy; celery running (`docker compose logs celery --tail=50`).

---

## Phase 5 — Edge proxy + TLS

```bash
docker compose up -d proxy
docker compose ps
docker compose logs proxy --tail=80
```

From an operator machine with DNS working:

```bash
curl -fsS -o /dev/null -w "%{http_code}\n" https://lahis.ohtk.org/
curl -fsS https://api.lahis.ohtk.org/health
curl -fsS https://api.lahis.ohtk.org/api/servers/
```

**TLS notes**

- First Caddy start may obtain certs (needs 80/443 and public DNS).
- `*.api.lahis.ohtk.org` wildcard often needs DNS-01; if tenant HTTPS fails, fix cert strategy before inviting users (HTTP lab or single-host workarounds are temporary only).

**Gate 5:** dashboard responds; API `/health` and `/api/servers/` over HTTPS.

---

## Phase 6 — Demo tenant (first empty DB)

django-tenants needs a client + domain. Example (adjust schema/name):

```bash
docker compose exec -T api python manage.py shell <<'PY'
from tenants.models import Client, Domain

schema = "demo"
host = "demo.api.lahis.ohtk.org"

client, created = Client.objects.get_or_create(
    schema_name=schema,
    defaults={"name": "LAHIS Demo"},
)
# Client may require extra fields depending on model; set if create fails.
print("client", client.id, "created=", created)

Domain.objects.update_or_create(
    domain=host,
    defaults={"tenant": client, "is_primary": True},
)
print("domain", host, "->", client.schema_name)
PY
```

If `Client` creation fails on required fields, inspect:

```bash
docker compose exec -T api python manage.py shell -c "from tenants.models import Client; print(Client._meta.fields)"
```

Then re-run with required fields set.

After domain exists:

```bash
# Public tenant list for dashboard
curl -fsS https://api.lahis.ohtk.org/api/servers/

# GraphQL typename on tenant host (TLS must work for that host)
curl -fsS -X POST https://demo.api.lahis.ohtk.org/graphql/ \
  -H 'content-type: application/json' \
  --data '{"query":"query { __typename }"}'
```

Create a staff/superuser if not bootstrapped via env:

```bash
docker compose exec -it api python manage.py createsuperuser
# Or with tenant context as required by your admin workflow
```

**Gate 6:** `/api/servers/` lists demo; GraphQL responds on tenant host; you can sign in on dashboard with server select.

---

## Phase 7 — Smoke suite

Automated checks (best effort; some need public DNS):

```bash
./scripts/smoke.sh
```

Manual extras:

| Check | How |
|-------|-----|
| Dashboard loads | Browser → `https://lahis.ohtk.org/` |
| Server list | Sign-in / server select uses `tenantsApiEndpoint` |
| Login | Cookie/JWT against tenant |
| Celery | `docker compose exec -T celery celery -A podd_api inspect ping` (if inspect works in image) |
| MinIO put | Upload avatar/report attachment; object appears under bucket `media/` prefix |
| WebSocket | Optional; needs working tenant session |

**Gate 7:** `./scripts/smoke.sh` exits 0 (or documented skips only).

---

## Phase 8 — Hand-off notes

Record on the host or team wiki:

```text
Date:
Host:
IMAGE_API=
IMAGE_MS=
DNS verified: yes/no
TLS wildcard status:
Demo tenant host:
Known issues:
```

Backup once after first good boot:

```bash
./scripts/backup.sh
ls -la /data/backups/
# Practice restore on a disposable host or after intentional snapshot:
# CONFIRM=RESTORE ./scripts/restore-pg.sh /data/backups/pg-....sql.gz
```

---

## Failure quick reference

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| api crash loop DB connection | db not ready / bad `.env` | Check `DB_*`, wait for healthy db |
| api still `runserver` / auto-migrate | old image | Rebuild/pin step 4+5 API image |
| MinIO access denied | wrong keys / no bucket | Re-run `bootstrap-minio.sh`; align AWS_* with MinIO user |
| `/api/servers/` empty | no Domain rows | Phase 6 tenant create |
| Tenant host 404/wrong schema | Host header / domain mismatch | Check `tenants_domain`, DNS, proxy Host |
| TLS fail on wildcard | ACME/DNS-01 | Temporary single-name certs; plan wildcard later |
| Dashboard wrong API | MS env | `serverDomain`, `tenantsApiEndpoint` in `.env` |

---

## Safe operations (ongoing)

| Do | Do not |
|----|--------|
| `./scripts/deploy.sh` with pinned digests | `docker compose down -v` |
| `./scripts/rollback.sh` if a release is bad | Set `RUN_MIGRATIONS=1` on shared staging api |
| `./scripts/migrate.sh --plan` then apply | Delete `/data/pg` or `/data/minio` casually |
| Backup before risky migrate | Deploy floating `latest` without `ALLOW_LATEST=1` (lab only) |

### App-only redeploy (after first boot)

```bash
cd /opt/lahis
./scripts/deploy.sh --api <image@sha256:...> --ms <image@sha256:...>
./scripts/smoke.sh
```

---

## Next after first boot (later steps)

- Schedule `./scripts/backup.sh` + off-box copy; practice `restore-pg.sh` once
- Wildcard TLS production strategy
- CI → SSH deploy with environment protection
