# LAHIS server installation and deployment

One-machine deployment bundle for the **LAHIS** API and dashboard.
Installation instructions reviewed against current source on **2026-10-20**;
execution and acceptance must be recorded for each host.

| Item | Decision |
|------|----------|
| Apps | `ohtk-api` (API + Celery) + `lahis-ms` (dashboard, branded) |
| Practice host | Single AWS EC2 (rehearsal only) |
| Final host | Bare metal (no AWS managed services) |
| Topology | **One machine, one-stop stack** |
| Object storage | **MinIO** on the same machine (S3-compatible API) |
| Domain now | `ohtk.org` (we control it) |
| Domain later | `lahis.org` (or equivalent); same topology, coordinated DNS/config/domain-row changes |

This directory holds deploy procedure docs and scripts.  
It does **not** replace app repos (`ohtk-api`, `lahis-ms` / upstream `ohtk-ms`).

**First time on a host:** follow [FIRST_BOOT.md](./FIRST_BOOT.md).

**Existing server image update:** follow [STAGING_DEPLOY_HANDOFF.md](./STAGING_DEPLOY_HANDOFF.md).
The first-boot runbook is the ordered installation procedure; the sections below
explain topology and operations. Historical step numbers and image-pin files
record implementation history, not a current release selection.

**External integrations:** use [INTEGRATION_GUIDELINE.md](./INTEGRATION_GUIDELINE.md)
for tenant-scoped OAuth, webhooks, idempotency, and the staging smoke gate.

### Available deployment components

| Step | Status | Artifact |
|------|--------|----------|
| 1 — Contract | done | [CONTRACT.md](./CONTRACT.md), [.env.example](./.env.example) |
| 2 — Compose skeleton | done | [compose.yml](./compose.yml), [proxy/Caddyfile](./proxy/Caddyfile), [RELEASE.example](./RELEASE.example) |
| 3 — Host bootstrap | done | [scripts/bootstrap-host.sh](./scripts/bootstrap-host.sh) |
| 4 — App runtime safety | done | `ohtk-api` entrypoint ASGI + gated migrate; [scripts/migrate.sh](./scripts/migrate.sh) |
| 5 — MinIO storage | done | API endpoint settings + [scripts/bootstrap-minio.sh](./scripts/bootstrap-minio.sh) |
| 6 — First boot runbook | done | [FIRST_BOOT.md](./FIRST_BOOT.md), [scripts/smoke.sh](./scripts/smoke.sh) |
| 7 — Deploy / rollback | done | [scripts/deploy.sh](./scripts/deploy.sh), [scripts/rollback.sh](./scripts/rollback.sh) |
| 8 — Backup / restore | done | [scripts/backup.sh](./scripts/backup.sh), restore-pg/minio |
| Historical image pins | examples only | [IMAGE_PINS.md](./IMAGE_PINS.md), [RELEASE.pins](./RELEASE.pins); select approved digests per release |
| Host acceptance | record per installation | [FIRST_BOOT.md](./FIRST_BOOT.md), including strict smoke, login, media, and backup evidence |

Later steps must follow contract names. Change [CONTRACT.md](./CONTRACT.md) first if something must rename.

---

## 1. Goals and non-goals

### Goals

- Deploy API + dashboard on **one host** for LAHIS staging.
- Practice the **same procedure** on AWS EC2 that will run on bare metal.
- Automate routine deploys **without human babysitting**, while keeping high-risk steps gated.
- Use **MinIO** for media/object storage so the final target never depends on AWS S3.
- Keep existing pre-staging (`backend.ohtk.org`, `admin.ohtk.org`, etc.) **untouched** via LAHIS-specific hostnames.

### Non-goals (v1)

- Multi-node HA, ALB, RDS, ElastiCache, ACM, EFS.
- Full production hardening beyond staging practice.
- Mobile store release (mobile may *point at* staging later).
- Replacing existing OHTK pre-staging with this stack.

---

## 2. Core principle: procedure portability

Design for **portable procedure**, not cloud services.

```text
same compose.yml
same .env.example
same deploy / migrate / backup scripts
same image digests
same health checks
same rollback
```

| Environment | What may differ |
|-------------|-----------------|
| AWS practice EC2 | Public IP, hostname under `ohtk.org`, disk size |
| Bare metal | NIC, IP, hostname under `lahis.org` later |
| **Must not differ** | Service graph, ports, env names, MinIO, deploy steps |

If a step only works on AWS (RDS, real S3, ALB health, EBS-only backups), it does **not** belong in the golden path.

**Success criterion:** install / deploy / migrate / backup / restore works the same on EC2 and bare metal. If bare metal needs different scripts, the practice failed.

---

## 3. One-machine service map

Everything that production will need runs on a single host:

```text
                    ┌─────────────────────────────────────────────┐
  Internet / LAN    │  one host (EC2 lab  ==  bare metal later)   │
                    │                                             │
  :443/:80 ────────►│  reverse proxy (Caddy or nginx)             │
                    │    lahis.ohtk.org        → ms:3000          │
                    │    api.lahis.ohtk.org    → api:8000         │
                    │    *.api.lahis.ohtk.org  → api:8000         │
                    │    minio.lahis.ohtk.org  → minio:9000       │
                    │                                             │
                    │  docker compose project: lahis              │
                    │    ms          (lahis-ms)                   │
                    │    api         (ASGI: Daphne)               │
                    │    celery      (same image, worker cmd)     │
                    │    celery-beat (same image, beat schedule)  │
                    │    redis                                    │
                    │    db          (postgis)                    │
                    │    minio                                    │
                    │                                             │
                    │  /data/pg  /data/redis  /data/minio         │
                    │  /data/backups                              │
                    └─────────────────────────────────────────────┘
```

| Service | Role |
|---------|------|
| `proxy` | TLS, Host routing, WebSocket upgrade |
| `ms` | Next.js dashboard (`lahis-ms`) |
| `api` | Django GraphQL + Channels (ASGI) |
| `celery` | Background tasks (worker) |
| `celery-beat` | Periodic schedule (CO3 auto-close; **one** replica only) |
| `db` | PostgreSQL + PostGIS |
| `redis` | Cache / broker / channels |
| `minio` | Object storage for media |

### Host sizing (starting point)

| Resource | Practice / small staging |
|----------|--------------------------|
| CPU / RAM | 2–4 vCPU, 8–16 GB RAM (e.g. EC2 `t3.large`) |
| Disk | 80–100 GB SSD (grows with PG + MinIO) |
| OS | Ubuntu 22.04 or 24.04 LTS (same on both environments) |
| Firewall | 80/443 public; SSH limited; **never** expose Postgres publicly |

---

## 4. DNS and branding (`ohtk.org` first)

Until `lahis.org` (or similar) is ready, use **LAHIS-scoped** names under `ohtk.org` so existing pre-staging is not collided with.

| Purpose | Hostname |
|---------|----------|
| Dashboard | `lahis.ohtk.org` |
| API (public / parent) | `api.lahis.ohtk.org` |
| Tenant hosts | `*.api.lahis.ohtk.org` (e.g. `demo.api.lahis.ohtk.org`) |
| MinIO (if public object URLs) | `minio.lahis.ohtk.org` |
| Tenant list for MS | `https://api.lahis.ohtk.org/api/servers/` |

**DNS records (all → the single machine IP):**

- `A`/`CNAME` for `lahis.ohtk.org`
- `A`/`CNAME` for `api.lahis.ohtk.org`
- `demo.api.lahis.ohtk.org`; add explicit DNS per additional tenant or wildcard DNS
- `minio.lahis.ohtk.org` for the documented public-media configuration

Tenant routing needs DNS **and** a matching database domain row and HTTPS site.
The supplied Caddyfile includes an explicit demo site, but its additional
wildcard site has no DNS-01 configuration. For the demo-only installation,
remove that wildcard site block before starting Caddy; see
[FIRST_BOOT.md](./FIRST_BOOT.md). Additional tenant sites need explicit certificates
or a configured wildcard certificate strategy.

### Later cutover to LAHIS domain

Keep the same Compose topology; change DNS, environment, proxy/TLS configuration,
and tenant domain rows together, for example:

| Now | Later (example) |
|-----|-----------------|
| `https://lahis.ohtk.org` | `https://app.lahis.org` |
| `api.lahis.ohtk.org` | `api.lahis.org` |
| `*.api.lahis.ohtk.org` | `*.api.lahis.org` |

Update tenant domain rows and MS env (`serverDomain`, `tenantsApiEndpoint`, `DASHBOARD_URL`) accordingly.

---

## 5. How API and dashboard run

### 5.1 Images

| App | Build source | Notes |
|-----|--------------|-------|
| `ohtk-api` | Approved build from the `ohtk-api` app repository | Record registry, source revision, digest, and platform per release |
| `lahis-ms` | Build from `lahis-ms` repo → public ECR `lahis-ms` | Runtime env override for staging hosts |

**Rule:** staging/production deploys use **pinned digests**, never floating `latest` alone.
`RELEASE.example`, `RELEASE.pins`, and `IMAGE_PINS.md` contain historical pins.
Replace them with the approved release; raw Compose commands must load `.env`
and then `RELEASE`, as shown in the first-boot runbook.

### 5.2 API (`ohtk-api`)

The current API runtime and Compose stack provide:

- Daphne ASGI server on `podd_api.asgi:application`
- Separate Celery worker process/container
- A separate singleton Celery Beat scheduler
- PostGIS database
- Redis for Celery broker and channels
- MinIO when media is object-stored
- Tenant domains mapped in DB (`tenants_client` / `tenants_domain`)

Illustrative env:

```text
DJANGO_DEBUG=False
DJANGO_SECRET_KEY=...
DJANGO_ALLOWED_HOSTS=.api.lahis.ohtk.org,api.lahis.ohtk.org
DASHBOARD_URL=https://lahis.ohtk.org
DB_* / REDIS_* / CELERY_BROKER_URL=...
USE_S3=True
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=lahis-media
AWS_S3_ENDPOINT_URL=http://minio:9000
FCM_DRY_RUN=True
```

**Migrations:** run via an explicit gated script (`migrate.sh`), not silently on every container start for shared staging data.

**Tenants (after first boot):**

1. Create / restore database.
2. Run `migrate_schemas` deliberately.
3. Create client + domain for e.g. `demo.api.lahis.ohtk.org`.
4. Confirm `GET /api/servers/` lists tenants for the dashboard.
5. Smoke GraphQL on the tenant host.

### 5.3 Dashboard (`lahis-ms`)

- Multi-stage Next.js standalone Docker image.
- Entrypoint can rewrite baked `.env.production` values from container env at runtime.

Staging inject:

```text
serverDomain=api.lahis.ohtk.org
tenantsApiEndpoint=https://api.lahis.ohtk.org/api/servers/
```

Serve at `https://lahis.ohtk.org` with HTTPS consistent with cookie/auth expectations.

### 5.4 Reverse proxy essentials

- TLS termination (Let’s Encrypt or operator-supplied certs)
- HTTP → HTTPS
- WebSocket upgrade for `/ws/`
- Forward original `Host` (django-tenants depends on it)
- Adequate body size for uploads / GraphQL multipart
- Optional basic auth on dashboard if staging must stay private
- MinIO console (`:9001`) not public — localhost / SSH tunnel only

### 5.5 MinIO

API uses `django-storages` / S3 API (`USE_S3=True`). MinIO is the long-term object store so bare metal never depends on AWS S3.

Supported configuration for the documented public-media mode:

```text
USE_S3=True
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=lahis-media
AWS_S3_REGION_NAME=us-east-1
AWS_S3_ENDPOINT_URL=http://minio:9000
AWS_S3_ADDRESSING_STYLE=path
AWS_S3_USE_SSL=False
AWS_S3_CUSTOM_DOMAIN=minio.lahis.ohtk.org/lahis-media
AWS_QUERYSTRING_AUTH=False
MINIO_PUBLIC_READ=1
```

The API settings already support the internal endpoint, path style, SSL setting,
and custom domain. The custom domain includes the bucket path. This mode makes
bucket objects anonymously downloadable; a private media deployment needs its
own reviewed access/URL configuration.

Bootstrap:

1. Start MinIO with data under `/data/minio`.
2. Create bucket `lahis-media` and app credentials via script (`bootstrap-minio.sh`).
3. Verify the anonymous-download policy and sentinel through `minio.lahis.ohtk.org`.
4. Upload through the app and verify the returned HTTPS media URL.

---

## 6. On-disk layout (same on EC2 and bare metal)

Installed layout under `/opt/lahis`:

```text
/opt/lahis/
  compose.yml
  proxy/Caddyfile
  ENV_NAME             # staging marker
  .env                 # secrets; mode 600; not in git
  .env.example
  RELEASE              # IMAGE_API=…@sha256:  IMAGE_MS=…
  scripts/
    bootstrap-host.sh
    bootstrap-minio.sh
    deploy.sh
    migrate.sh
    backup.sh
    restore-pg.sh
    restore-minio.sh
    smoke.sh
    rollback.sh
```

Internal compose networking:

| From | To |
|------|-----|
| api / celery / celery-beat | `db:5432` |
| api / celery / celery-beat | `redis:6379` |
| api | `http://minio:9000` |

Data directories on host disk:

```text
/data/pg
/data/redis
/data/minio
/data/backups
/data/caddy/data
/data/caddy/config
```

---

## 7. Golden procedure

### A. Host bootstrap (once per machine)

1. Install Ubuntu LTS.
2. Create `deploy` user; harden SSH / access.
3. Run `sudo DEPLOY_USER=deploy ./scripts/bootstrap-host.sh` from the approved bundle.
   It installs Docker/Compose, creates directories, and copies the bundle to `/opt/lahis`.
4. Reconnect for Docker group membership; fill `/opt/lahis/.env` (mode 600).
5. Set approved API/dashboard digests in `RELEASE`; do not reuse historical example pins blindly.
6. Prepare DNS, explicit tenant HTTPS sites, and firewall: 80/443 public; restrict SSH.
   The bootstrap script leaves firewall configuration unchanged by default.

Optional later: a small Ansible role that only does the above, with inventory hosts `lahis-aws-lab` and `lahis-baremetal`.

### B. First boot

Follow [FIRST_BOOT.md](./FIRST_BOOT.md) for commands and gates:

1. Load `.env`, then `RELEASE`; validate host identity, secrets, image digests, and Compose; pull images.
2. `up -d db redis minio`; wait healthy.
3. Bootstrap MinIO bucket + keys.
4. Review the shared-schema migration plan for the empty database; run `migrate.sh` **before apps start**.
5. Start `api celery celery-beat ms`, check health, then start the prepared HTTPS proxy.
6. Create tenant + domain rows and a tenant-scoped administrator.
7. Run `SMOKE_STRICT=1 ./scripts/smoke.sh`; verify tenant login and media upload/read.
8. Back up PostgreSQL and MinIO, arrange an off-host copy, and record acceptance evidence.

### C. App deploy (repeatable)

1. CI builds images → tags `sha-…` / digests.
2. Approve the new digests; supply them to `deploy.sh --api '…@sha256:…' --ms '…@sha256:…'`.
   Preserve the current `RELEASE` until the script snapshots it for rollback.
3. `deploy.sh`: snapshot current release → write new pins → pull → recreate selected app services → health checks
   (default: `api celery celery-beat ms`).
4. On failure: restore previous `RELEASE` digests and bring services back up.

Migrations are **not** in this path unless a separate approved job runs `migrate.sh`.

### D. Backup / restore (must work without AWS services)

Daily (cron):

- `pg_dump` → `/data/backups/pg-YYYYMMDD.sql.gz`
- Optional MinIO mirror → `/data/backups/minio-…`
- Copy off-box (rsync, second disk, another host)

Restore drill (practice once on EC2):

- Follow the restore scripts for the selected backup on a disposable host;
  stop all database writers, including API, worker, and Beat, for an in-place restore.
- Verify the restored database, media, and separately secured secrets before acceptance.

---

## 8. Safe automation (unattended but controlled)

Automate execution of an **approved path**. Humans approve risk; machines deploy.

### Safe to automate

| Action | Notes |
|--------|--------|
| CI test + build image | Immutable tags/digests |
| Pull + restart api / ms / celery / celery-beat | Health checks required; one Beat replica |
| Auto-rollback on failed health | Previous `RELEASE` digests |
| Daily backup scripts | Cron on host |
| Smoke tests after deploy | Fail → rollback |

### Always human-gated (or strongly protected)

| Action | Why |
|--------|-----|
| First host bootstrap | Fingerprint of the machine |
| `migrate_schemas` | Data risk; show plan first |
| DB restore / overwrite | Destructive |
| DNS / cert ownership changes | External blast radius |
| Any volume wipe / `compose down -v` | **Banned** from automation |
| Promote staging → real production | Explicit promote only |

### Control rails

- Deploy only by **digest** recorded in `RELEASE`.
- Fixed compose project name: `lahis`.
- Host allowlist or required `ENV_NAME=staging` marker file.
- Mutex: `flock /opt/lahis/.deploy.lock`.
- Deploy log: who, which git sha, which digests, result.
- No silent `DROP` / volume delete / force recreate of data services.

### Deploy trigger options (pick one later)

1. CI SSH → host runs `deploy.sh` (works on bare metal).
2. Host pulls a `RELEASE` file (simple, low moving parts).
3. `workflow_dispatch` with environment protection rules.

Do **not** design around ECS, CodeDeploy, or other AWS-only deploy products.

### Approval matrix

| Action | Automated? | Human gate? |
|--------|------------|-------------|
| Build + push image | Yes on green CI | No |
| Deploy app containers to staging | Yes | Optional reviewer for first weeks |
| Run migrations | Semi | **Always** plan review + approval |
| Restore / overwrite DB | No | Human only |
| Change DNS | Rare | Human |
| Destroy host or `/data` | No | Human (+ two-person if possible) |

### Minimum smoke tests after every deploy

1. API health endpoint (or HealthCheckMiddleware path).
2. `GET https://api.lahis.ohtk.org/api/servers/` returns tenant JSON.
3. GraphQL `query { __typename }` on public + one tenant host.
4. Dashboard root loads: `https://lahis.ohtk.org/`.
5. Login / JWT cookie path against a seed user (when available).
6. Celery ping or trivial task.
7. Optional: WebSocket handshake on a known path.
8. Media upload lands in MinIO and its returned HTTPS URL is readable.

For installation acceptance, strict smoke must have no failures or skips.
Its GraphQL probe checks HTTP status; separately inspect GraphQL JSON and verify
login/media behavior as described in the first-boot runbook.

For a failed app update, use the previous approved images when image rollback is
appropriate. On first boot there is no previous release: stop at the failed gate
and diagnose it. Image rollback does not undo database migrations.

---

## 9. What DevOps needs (checklist)

### Access and identity

- [ ] One Ubuntu target (EC2 practice; bare metal later) with sudo
- [ ] DNS admin for `lahis*.ohtk.org` + API wildcard
- [ ] Read access to API + MS container registries
- [ ] GitHub (or other) permissions to build/publish and trigger deploy
- [ ] SSH (or equivalent) to the single host for deploy agent

### Secrets (never in git)

- [ ] `DJANGO_SECRET_KEY`
- [ ] DB credentials
- [ ] MinIO root + application keys
- [ ] Optional SMTP
- [ ] Optional Firebase key only if push is tested (`FCM_DRY_RUN` otherwise)
- [ ] Optional dashboard basic-auth password

### Written decisions

- [ ] Exact hostnames (section 4)
- [ ] Which git ref deploys staging (`fao-feature` vs tags vs `main`)
- [ ] Fresh DB vs anonymized copy (and anonymization rules if copy)
- [ ] Public staging vs VPN / basic-auth
- [ ] Who approves migrations
- [ ] Public MinIO URL vs media via API only
- [ ] Image registry strategy (keep split GHCR/ECR or mirror locally)

### Explicitly not required for golden path

- RDS, S3, ALB, ACM, ElastiCache, EFS
- Multi-node orchestration
- CloudWatch as a hard dependency (journald + files first)
- AWS IAM for **runtime** storage (MinIO keys in `.env`)

---

## 10. Checks before accepting a host

| Check | Why it matters |
|-----|----------------|
| Approved pinned app images and platform | Source support does not prove an older image includes it |
| Daphne with `RUN_MIGRATIONS=0` | Runtime and migrations remain separately controlled |
| All eight Compose services, with one Beat | Complete runtime and periodic scheduling |
| Tenant DNS, database domain, and TLS agree | Wildcard DNS alone does not configure certificates |
| MinIO app write and public HTTPS read | Bucket setup alone does not prove the full media flow |
| Dashboard runtime API settings and tenant login | Image defaults may point at another environment |
| PostgreSQL and MinIO backup plus restore drill | A successful dump alone does not prove recoverability |

ASGI, gated migrations, MinIO settings, and the full Compose service graph are
implemented. Verify the selected images and host results rather than treating
these as pending code changes or assuming source review proves an installation.

---

## 11. Practice schedule

| Step | On AWS EC2 | Proves for bare metal |
|------|------------|------------------------|
| 1 | Bootstrap host like bare metal | Install checklist |
| 2 | Full compose with MinIO | Service graph |
| 3 | TLS + tenant wildcard DNS | Proxy + tenants |
| 4 | Upload via API → object in MinIO | Storage path |
| 5 | `deploy.sh` new digests + rollback | Unattended app update |
| 6 | `migrate.sh` with approval | Safe schema change |
| 7 | Backup + restore drill | Disaster recovery |
| 8 | Confirm no hidden AWS service deps | Portable procedure |

---

## 12. Relation to existing assets

| Asset | Reuse? | Note |
|-------|--------|------|
| `ohtk-api` Dockerfile + CI image publish | Yes | Prefer ASGI command for deploy |
| `lahis-ms` Dockerfile + ECR `lahis-ms` | Yes | Brand fork of `ohtk-ms`; deploy this for LAHIS |
| `ohtk-api/docker/docker-compose.yml` | Partial | Lab only; not full LAHIS stack |
| `ohtk-ansible` | Mostly legacy | Prefer compose + host scripts |
| Current `backend.ohtk.org` / `admin.ohtk.org` | Leave alone | New `lahis.*` names avoid collisions |

---

## 13. Open decisions

Defaults for first staging are recorded in [CONTRACT.md §8](./CONTRACT.md). Remaining product choices:

1. **Release inputs:** record approved source revisions, image digests, and platform per deployment
2. **DB seed strategy:** default **empty** + demo tenant (change in CONTRACT if copy preferred)
3. **Staging exposure:** default **public HTTPS** (basic-auth optional later)
4. **Migration approvers:** _TBD_
5. **Mobile pointed at this staging in v1?** _TBD_
6. **Registry unification vs keep split:** _TBD_
7. **Public MinIO media URLs:** supported default `minio.lahis.ohtk.org/lahis-media`; requires anonymous-download policy

---

## 14. Next artifacts (this directory)

- [x] `CONTRACT.md` — frozen names (step 1)
- [x] `.env.example` — env var contract (step 1)
- [x] `compose.yml` — one-box skeleton **(step 2)**
- [x] `proxy/Caddyfile` — edge routing skeleton **(step 2)**
- [x] `RELEASE.example` — image pin template **(step 2)**
- [x] `scripts/bootstrap-host.sh` **(step 3)**
- [x] App runtime: ASGI + migrate gate **(step 4)** — in `ohtk-api` + `scripts/migrate.sh`
- [x] MinIO endpoint support in `ohtk-api` **(step 5)**
- [x] `scripts/bootstrap-minio.sh` **(step 5)**
- [x] First-boot runbook **(step 6)** — [FIRST_BOOT.md](./FIRST_BOOT.md)
- [x] `scripts/smoke.sh` **(step 6)**
- [x] `scripts/migrate.sh` (step 4 companion)
- [x] `scripts/deploy.sh` + `rollback.sh` **(step 7)**
- [x] `scripts/backup.sh` + `restore-pg.sh` + `restore-minio.sh` **(step 8)**
- [ ] Record first-boot acceptance for each new host (this document is not a live execution record)
- [ ] Optional Ansible role for host bootstrap only
- [ ] CI → SSH deploy wiring

---

## 15. Deployment boundary

- **Final deploy target:** one bare-metal machine, Docker Compose, MinIO, no AWS managed services.
- **AWS:** disposable **rehearsal** of that exact stack.
- **Automate:** image pull, app recreation, health, image rollback, backups.
- **Do not automate blind:** migrations, restores, volume destruction.
- **Domain now:** LAHIS names under `ohtk.org`; later cutover coordinates DNS, env, proxy/TLS, tenant domains, and media URLs.
