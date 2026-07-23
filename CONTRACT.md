# LAHIS staging contract (step 1)

Frozen names for the one-machine LAHIS stack.  
Practice host (AWS EC2) and final host (bare metal) share this contract.

**Status:** agreed for planning  
**Last updated:** 2026-07-14  
**Supersedes:** informal notes in chat; detail still in [README.md](./README.md)

If a later step needs a different name, update **this file first**, then compose/scripts.

---

## 1. Environment identity

| Key | Value |
|-----|--------|
| Brand / app name | LAHIS |
| Feature track | FAO-feature |
| Compose project name | `lahis` |
| Deploy root on host | `/opt/lahis` |
| Env marker file | `/opt/lahis/ENV_NAME` content: `staging` |
| Practice domain zone | `ohtk.org` |
| Final domain zone | `lahis.org` (or equivalent; cut over later) |

---

## 2. Hostnames (practice on `ohtk.org`)

All A/AAAA (or CNAME) records point at the **same single machine**.

| Role | Hostname | Notes |
|------|----------|--------|
| Dashboard | `lahis.ohtk.org` | HTTPS → `ms:3000` |
| API parent | `api.lahis.ohtk.org` | HTTPS → `api:8000` |
| Tenant wildcard | `*.api.lahis.ohtk.org` | Same backend; django-tenants Host resolution |
| Example tenant | `demo.api.lahis.ohtk.org` | First demo tenant host |
| MinIO API (public, optional) | `minio.lahis.ohtk.org` | HTTPS → `minio:9000`; console not public |
| Tenant list URL | `https://api.lahis.ohtk.org/api/servers/` | MS `tenantsApiEndpoint` |
| GraphQL (tenant) | `https://<tenant>.api.lahis.ohtk.org/graphql/` | |

### Later cutover (example only; not active yet)

| Practice | Later |
|----------|--------|
| `lahis.ohtk.org` | `app.lahis.org` |
| `api.lahis.ohtk.org` | `api.lahis.org` |
| `*.api.lahis.ohtk.org` | `*.api.lahis.org` |
| `minio.lahis.ohtk.org` | `minio.lahis.org` |

Cutover = DNS + `.env` + tenant domain rows. **No** topology change.

---

## 3. Compose services (fixed names)

| Service | Container role | Public port on host |
|---------|----------------|---------------------|
| `proxy` | Caddy or nginx (TLS + routing) | 80, 443 |
| `ms` | `lahis-ms` dashboard (branded) | internal 3000 |
| `api` | `ohtk-api` ASGI web | internal 8000 |
| `celery` | `ohtk-api` worker | none |
| `db` | PostGIS | internal 5432 only |
| `redis` | Redis | internal 6379 only |
| `minio` | MinIO S3 API | internal 9000 (9001 console = local only) |

Do not rename these without updating the whole deploy bundle.

---

## 4. Data paths on host

| Path | Purpose |
|------|---------|
| `/opt/lahis` | Deploy bundle (compose, scripts, `.env`, `RELEASE`) |
| `/data/pg` | Postgres data |
| `/data/redis` | Redis data (if persisted) |
| `/data/minio` | MinIO objects |
| `/data/backups` | `pg_dump` and optional MinIO mirrors |

Automation must never delete these paths or run `docker compose down -v`.

---

## 5. Images and release pin

| App | Image source (current CI reality) | Pin style |
|-----|-----------------------------------|-----------|
| API | e.g. `ghcr.io/onehealthtoolkit/ohtk-api` | digest or `sha-<gitsha>` |
| Dashboard | e.g. public ECR `lahis-ms` | digest or `sha-<gitsha>` |

On host, digests live in:

```text
/opt/lahis/RELEASE
```

Example shape (exact format locked when `deploy.sh` is written):

```text
IMAGE_API=ghcr.io/onehealthtoolkit/ohtk-api@sha256:...
IMAGE_MS=public.ecr.aws/.../lahis-ms@sha256:...
```

Deploy **must not** rely on floating `latest` alone.

---

## 6. Environment variables

Canonical list: [`.env.example`](./.env.example).

### Groups

| Group | Used by | Notes |
|-------|---------|--------|
| Host / deploy | scripts | `ENV_NAME`, paths, image refs |
| Django core | `api`, `celery` | secret, debug, allowed hosts, dashboard URL |
| Database | `api`, `celery`, `db` | PostGIS |
| Redis / Celery | `api`, `celery` | broker + channel layer |
| Object storage | `api`, `celery` | MinIO via S3-compatible settings |
| Email | `api`, `celery` | optional on first staging |
| Firebase / FCM | `api`, `celery` | `FCM_DRY_RUN=True` default |
| Bootstrap superuser | first boot only | optional; empty = skip |
| Dashboard | `ms` | `serverDomain`, `tenantsApiEndpoint` |
| MinIO server | `minio` | root user/password for the service itself |
| Proxy / TLS | `proxy` | domain list for ACME if used |

### App code vs deploy-planned keys

**Already read by `ohtk-api` today** (via `podd_api/settings.py` / image env):

- `DJANGO_SECRET_KEY`, `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`
- `DB_*`, `REDIS_HOST`, `REDIS_PORT`, `CELERY_BROKER_URL`
- `USE_S3`, `AWS_*`, `S3_MEDIA_BUCKET_NAME`
- `DASHBOARD_URL`, `EMAIL_*`, `EMAIL_DOMAIN`
- `FCM_DRY_RUN`, `FIREBASE_PRIVATE_KEY`
- `CELERY_TASK_ALWAYS_EAGER`, `USE_INMEMORY_CHANNEL_LAYER`
- `DJANGO_SUPERUSER_*` (entrypoint bootstrap)

**Already used by `lahis-ms` (dashboard):**

- `serverDomain`
- `tenantsApiEndpoint`

**MinIO / S3-compatible (ohtk-api step 5+):**

- `AWS_S3_ENDPOINT_URL` (e.g. `http://minio:9000`)
- `AWS_S3_CUSTOM_DOMAIN` (e.g. `minio.lahis.ohtk.org`)
- `AWS_S3_ADDRESSING_STYLE` (default `path` when endpoint set)
- `AWS_S3_USE_SSL` (false for internal `http://minio:9000`)
- `AWS_DEFAULT_ACL` / `AWS_QUERYSTRING_AUTH` as needed

Do not invent alternate names in compose; extend the app if missing.

---

## 7. Internal service DNS (compose network)

| Consumer | Target |
|----------|--------|
| api / celery → DB | `db:5432` |
| api / celery → Redis | `redis:6379` |
| api → MinIO | `http://minio:9000` |
| proxy → api | `http://api:8000` |
| proxy → ms | `http://ms:3000` |
| proxy → minio | `http://minio:9000` |

---

## 8. Defaults for open product decisions

Locked **defaults** so step 2 can proceed. Change here if you disagree.

| Decision | Default for first staging |
|----------|---------------------------|
| Git ref that feeds staging images | _TBD — record before first real deploy_ |
| First DB | **Empty** (migrate + seed demo tenant), not a blind copy of pre-staging |
| Staging exposure | **HTTPS public** + optional dashboard basic-auth later if needed |
| Migrations | **Human-approved** `migrate.sh` only; not on every container start |
| FCM | `FCM_DRY_RUN=True` |
| Email | optional / empty until needed |
| First demo tenant schema host | `demo.api.lahis.ohtk.org` |
| MinIO bucket name | `lahis-media` |
| Media public access | Use `minio.lahis.ohtk.org/<bucket>` (path-style) once endpoint wiring exists; until then local disk only for short lab |

---

## 9. Safety rails (contract level)

| Rule | Value |
|------|--------|
| Compose project | always `lahis` |
| Forbidden automated actions | `docker compose down -v`, delete `/data/*`, unapproved migrate |
| Deploy pin | digests in `RELEASE` |
| Mutex path (future) | `/opt/lahis/.deploy.lock` |
| Secrets file | `/opt/lahis/.env` mode `600`, never committed |

---

## 10. Done criteria for step 1

- [x] Hostnames frozen for practice
- [x] Service names and data paths frozen
- [x] Env var names listed in `.env.example`
- [x] Defaults recorded for empty DB, MinIO bucket, demo tenant
- [ ] Team review: confirm hostname set and empty-DB default (no code change required)

**Next step (step 2):** `compose.yml` skeleton using only names from this contract (placeholder image digests, no live host required).

---

## 11. Step 2 — compose skeleton

**Status:** done (skeleton only; not production-ready runtime)

| File | Purpose |
|------|---------|
| [compose.yml](./compose.yml) | All services: `db`, `redis`, `minio`, `api`, `celery`, `ms`, `proxy` |
| [proxy/Caddyfile](./proxy/Caddyfile) | Host routing per contract hostnames |
| [RELEASE.example](./RELEASE.example) | Image pin template |

**Done criteria**

- [x] Service names match §3
- [x] Data binds under `${DATA_ROOT}` (`/data` by default)
- [x] Env wired from `.env` / contract names
- [x] No public ports on `db` / `redis`
- [x] Placeholder images documented (not digest-pinned yet)

**Still deferred**

- Host bootstrap + real digests
- ASGI entrypoint / no migrate-on-start
- MinIO bucket bootstrap script + API endpoint support
- Full TLS wildcard strategy
- `deploy.sh` / smoke / backup scripts

**Next step (step 3):** host bootstrap notes/script for one Ubuntu box (`bootstrap-host.sh`) — create dirs, install Docker, place bundle, no full app bring-up yet.

---

## 12. Step 3 — host bootstrap

**Status:** done (script only; not yet run on a live host)

| File | Purpose |
|------|---------|
| [scripts/bootstrap-host.sh](./scripts/bootstrap-host.sh) | Ubuntu prep: Docker, `/opt/lahis`, `/data/*`, seed `.env`/`RELEASE` |
| [scripts/README.md](./scripts/README.md) | Script usage |

**Done criteria**

- [x] Creates contract paths under `/opt/lahis` and `/data`
- [x] Installs Docker Engine + Compose plugin (optional skip)
- [x] Writes `ENV_NAME=staging` marker
- [x] Seeds `.env` / `RELEASE` without overwriting existing secrets
- [x] Does **not** start compose or run migrations

**Still deferred**

- First boot / `compose up`
- MinIO bucket bootstrap
- App runtime fixes (ASGI, migrate gate, MinIO endpoint)
- deploy / smoke / backup scripts

**Next step (step 4):** pick one path — either (A) first-boot runbook + data-plane only `compose up` notes, or (B) app runtime fixes (ASGI entrypoint + no auto-migrate) so first boot is safer. Recommend **B** before public first boot.

---

## 13. Step 4 — app runtime safety

**Status:** done in `ohtk-api` source (requires a new API image build before hosts pick it up)

| Change | Location |
|--------|----------|
| ASGI via **daphne** (not `runserver`) | `ohtk-api/docker-entrypoint.sh` |
| Migrations **gated** (`RUN_MIGRATIONS` truthy only) | same; uses `migrate_schemas --noinput` |
| Celery entrypoint cleaned up | `ohtk-api/celery-entrypoint.sh` |
| Explicit migrate helper | [scripts/migrate.sh](./scripts/migrate.sh) (`--plan` or apply) |
| Staging default | `RUN_MIGRATIONS=0` in `.env.example` / compose |

**Done criteria**

- [x] Web container starts ASGI (Channels/WebSocket capable)
- [x] Shared staging does not migrate on every restart by default
- [x] Lab can still opt in with `RUN_MIGRATIONS=True`
- [x] Out-of-band migrate path documented (`scripts/migrate.sh`)

**Operator note:** until a new image is built and pinned in `RELEASE`, existing published images still use the old entrypoint. Rebuild/publish `ohtk-api` before first LAHIS boot.

**Next step (step 5):** MinIO endpoint support in `ohtk-api` settings/storage **or** first-boot runbook (data plane → migrate → apps). Prefer MinIO wiring if media is in scope for first smoke.

---

## 14. Step 5 — MinIO / S3-compatible storage

**Status:** done in `ohtk-api` source + deploy bootstrap script (needs new API image on host)

| Change | Location |
|--------|----------|
| Endpoint / path-style / custom domain / ACL settings | `ohtk-api/podd_api/settings.py` |
| Storage class passes MinIO options | `ohtk-api/common/storage.py` |
| Unit tests | `ohtk-api/common/tests/test_storage_s3.py` |
| Bucket bootstrap | [scripts/bootstrap-minio.sh](./scripts/bootstrap-minio.sh) |

**Done criteria**

- [x] `USE_S3=True` + `AWS_S3_ENDPOINT_URL=http://minio:9000` is first-class
- [x] Real AWS S3 still works when endpoint is unset
- [x] Bucket create script for one-box MinIO
- [x] Targeted tests pass

**Next step (step 6):** first-boot runbook — data plane up → MinIO bootstrap → migrate → api/celery/ms/proxy → smoke.

---

## 15. Step 6 — first boot runbook

**Status:** done (documentation + smoke script; not yet executed on a live host)

| File | Purpose |
|------|---------|
| [FIRST_BOOT.md](./FIRST_BOOT.md) | Phased operator procedure with gates |
| [scripts/smoke.sh](./scripts/smoke.sh) | Post-boot checks (compose + optional public HTTPS) |

**Phases**

0. Preflight → 1. Data plane → 2. MinIO bucket → 3. Migrate → 4. api/celery/ms → 5. proxy/TLS → 6. Demo tenant → 7. Smoke → 8. Hand-off + backup

**Next step (step 7):** `scripts/deploy.sh` + `rollback.sh` for repeatable app image updates (digest pin, health, rollback).

---

## 16. Step 7 — deploy / rollback

**Status:** done (scripts; needs live host + pinned images to exercise)

| File | Purpose |
|------|---------|
| [scripts/deploy.sh](./scripts/deploy.sh) | Pull + recreate api/celery/ms; health; auto-rollback |
| [scripts/rollback.sh](./scripts/rollback.sh) | Restore `RELEASE.prev` or history file |
| [scripts/lib/common.sh](./scripts/lib/common.sh) | Lock, release load, health wait |

**Rules**

- Mutex: `.deploy.lock`
- Requires `ENV_NAME` marker
- Refuses `:latest` unless `ALLOW_LATEST=1`
- Does **not** run migrations or touch data volumes
- On health failure: restore `RELEASE.prev` and recreate services

**Next step (step 8):** backup/restore scripts (`backup.sh`, `restore-pg.sh`) and scheduled backup notes.

---

## 17. Step 8 — backup / restore

**Status:** done (scripts; practice restore once on staging before trusting)

| File | Purpose |
|------|---------|
| [scripts/backup.sh](./scripts/backup.sh) | `pg_dump` + optional MinIO mirror + redacted config snapshot |
| [scripts/restore-pg.sh](./scripts/restore-pg.sh) | Destructive PG restore (`CONFIRM=RESTORE`) |
| [scripts/restore-minio.sh](./scripts/restore-minio.sh) | Mirror backup dir back into MinIO (`CONFIRM=RESTORE`) |

**Backup location:** `${DATA_ROOT}/backups` (default `/data/backups`)  
**Retention:** `RETAIN_DAYS` (default 14)  
**Gate:** restore requires `CONFIRM=RESTORE`  
**Note:** local backups are not DR until copied off-box

**Suggested next steps (optional program work):**

- CI → SSH deploy using `deploy.sh`
- Wildcard TLS hardening
- Run first boot on real EC2 practice host
- Off-box backup rsync job
