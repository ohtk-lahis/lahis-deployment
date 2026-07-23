# LAHIS deployment plan

First staging and production-shaped deploy for the **FAO-feature** stack under the **LAHIS** brand.

| Item | Decision |
|------|----------|
| Apps | `ohtk-api` (API + Celery) + `lahis-ms` (dashboard, branded) |
| Practice host | Single AWS EC2 (rehearsal only) |
| Final host | Bare metal (no AWS managed services) |
| Topology | **One machine, one-stop stack** |
| Object storage | **MinIO** on the same machine (S3-compatible API) |
| Domain now | `ohtk.org` (we control it) |
| Domain later | `lahis.org` (or equivalent); same topology, DNS + env only |

This directory holds deploy procedure docs and scripts.  
It does **not** replace app repos (`ohtk-api`, `lahis-ms` / upstream `ohtk-ms`).

**First time on a host:** follow [FIRST_BOOT.md](./FIRST_BOOT.md).

**External integrations:** use [INTEGRATION_GUIDELINE.md](./INTEGRATION_GUIDELINE.md)
for tenant-scoped OAuth, webhooks, idempotency, and the staging smoke gate.

### Progress

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
| Image pin (local) | done | [IMAGE_PINS.md](./IMAGE_PINS.md), [RELEASE.pins](./RELEASE.pins) |
| — Practice on host | next | Transfer/push API image → first boot |

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
same .env.template
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
                    │    api         (ASGI: daphne/uvicorn)       │
                    │    celery      (same image, worker cmd)     │
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
| `celery` | Background tasks |
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
- Wildcard `*.api.lahis.ohtk.org` (required for django-tenants Host resolution)
- Optional: `minio.lahis.ohtk.org`

### Later cutover to LAHIS domain

Same compose; change DNS + env only, for example:

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
| `ohtk-api` | CI on app repo (e.g. GHCR `ghcr.io/onehealthtoolkit/ohtk-api`) | Prefer immutable `sha-<gitsha>` or digest |
| `lahis-ms` | Build from `lahis-ms` repo → public ECR `lahis-ms` | Runtime env override for staging hosts |

**Rule:** staging/production deploys use **pinned digests**, never floating `latest` alone.

### 5.2 API (`ohtk-api`)

Stack needs:

- ASGI server (daphne/uvicorn) on `podd_api.asgi:application` — **not** long-term `runserver`
- Separate Celery worker process/container
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

Planned config shape:

```text
USE_S3=True
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=lahis-media
AWS_S3_REGION_NAME=us-east-1
AWS_S3_ENDPOINT_URL=http://minio:9000
# plus path-style / custom domain as needed for public media URLs
```

**Code gap:** endpoint / path-style / custom domain may need explicit wiring in `ohtk-api` settings/storage before MinIO is first-class. Until then, practice may fall back to local disk (`USE_S3=False`) only for short lab — that is **not** the production-shaped path.

Bootstrap:

1. Start MinIO with data under `/data/minio`.
2. Create bucket `lahis-media` and app credentials via script (`bootstrap-minio.sh`).
3. Decide public URL strategy: proxy `minio.lahis.ohtk.org` vs media only via API/nginx.

---

## 6. On-disk layout (same on EC2 and bare metal)

Target layout under `/opt/lahis` (to be added as files in this directory over time):

```text
/opt/lahis/
  compose.yml
  Caddyfile | nginx.conf
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
    smoke.sh
    rollback.sh
```

Internal compose networking:

| From | To |
|------|-----|
| api / celery | `db:5432` |
| api / celery | `redis:6379` |
| api | `http://minio:9000` |

Data directories on host disk:

```text
/data/pg
/data/redis
/data/minio
/data/backups
```

---

## 7. Golden procedure

### A. Host bootstrap (once per machine)

1. Install Ubuntu LTS.
2. Create `deploy` user; harden SSH / access.
3. Install Docker Engine + Compose plugin.
4. Create `/opt/lahis` and `/data/{pg,redis,minio,backups}`.
5. Place deploy bundle (this repo’s future files) under `/opt/lahis`.
6. Copy secrets to `/opt/lahis/.env` (mode 600).
7. Firewall: 80/443 only for public; restrict SSH.

Optional later: a small Ansible role that only does the above, with inventory hosts `lahis-aws-lab` and `lahis-baremetal`.

### B. First boot

1. `docker compose pull` (pinned digests).
2. `up -d db redis minio`; wait healthy.
3. Bootstrap MinIO bucket + keys.
4. `up -d api celery ms proxy`.
5. One-time: run `migrate.sh` (explicit).
6. Create tenant + domain rows.
7. Run smoke tests.

### C. App deploy (repeatable)

1. CI builds images → tags `sha-…` / digests.
2. Host updates `RELEASE` with digests.
3. `deploy.sh`: pull → `compose up -d api celery ms` → health checks.
4. On failure: restore previous `RELEASE` digests and bring services back up.

Migrations are **not** in this path unless a separate approved job runs `migrate.sh`.

### D. Backup / restore (must work without AWS services)

Daily (cron):

- `pg_dump` → `/data/backups/pg-YYYYMMDD.sql.gz`
- Optional MinIO mirror → `/data/backups/minio-…`
- Copy off-box (rsync, second disk, another host)

Restore drill (practice once on EC2):

- Stop api/celery → restore dump → start → smoke

---

## 8. Safe automation (unattended but controlled)

Automate execution of an **approved path**. Humans approve risk; machines deploy.

### Safe to automate

| Action | Notes |
|--------|--------|
| CI test + build image | Immutable tags/digests |
| Pull + restart api / ms / celery | Health checks required |
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
8. Optional: media upload lands in MinIO.

Any failure → **rollback images**, do not “fix forward” blind.

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

## 10. Gaps to close before trusting automation

| Gap | Why it matters |
|-----|----------------|
| API entrypoint uses `runserver` | Weak for real traffic / Channels WebSockets |
| Unconditional migrate on container start | Dangerous once real data exists |
| No first-class MinIO endpoint settings | Forces AWS S3 or local files; breaks bare-metal story |
| Lab compose lacks celery + proxy + minio | Procedure incomplete |
| Floating `latest` only | Audit and rollback fail |
| MS image bakes prod `*.ohtk.org` defaults | Must verify runtime override for LAHIS staging |

**Priority order**

1. MinIO-compatible storage settings in `ohtk-api`
2. Production ASGI entrypoint + migrate not on every boot
3. Full one-box compose + scripts in this directory
4. Manual golden path on EC2
5. Automate `deploy.sh` only after manual path is boring

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

1. **Git ref for staging builds:** _TBD — set before first real image deploy_
2. **DB seed strategy:** default **empty** + demo tenant (change in CONTRACT if copy preferred)
3. **Staging exposure:** default **public HTTPS** (basic-auth optional later)
4. **Migration approvers:** _TBD_
5. **Mobile pointed at this staging in v1?** _TBD_
6. **Registry unification vs keep split:** _TBD_
7. **Public MinIO media URLs:** default prefer `minio.lahis.ohtk.org` once endpoint wiring exists

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
- [ ] Practice first boot on real host
- [ ] Optional Ansible role for host bootstrap only
- [ ] CI → SSH deploy wiring

---

## 15. Bottom line

- **Final deploy target:** one bare-metal machine, Docker Compose, MinIO, no AWS managed services.
- **AWS:** disposable **rehearsal** of that exact stack.
- **Automate:** image pull, rolling restart, health, rollback, backups.
- **Do not automate blind:** migrations, restores, volume destruction.
- **Domain now:** LAHIS names under `ohtk.org`; cut over to `lahis.org` later via DNS + env only.
