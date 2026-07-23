# LAHIS deploy scripts

| Script | Step | What it does | What it does **not** do |
|--------|------|--------------|-------------------------|
| [bootstrap-host.sh](./bootstrap-host.sh) | 3 | Ubuntu host prep: Docker, dirs, place bundle, seed `.env`/`RELEASE` | Start stack, migrate, pull app images, configure DNS |
| [migrate.sh](./migrate.sh) | 4 | `migrate_schemas` via one-off api container; `--plan` or apply | Start web/proxy permanently; invent credentials |
| [bootstrap-minio.sh](./bootstrap-minio.sh) | 5 | Ensure MinIO up, create bucket, optional public-read | Start API; configure DNS/TLS |
| [smoke.sh](./smoke.sh) | 6 | Running services, DB/Redis/MinIO, api `/health`, optional public HTTPS | Fix root cause; create tenants |
| [deploy.sh](./deploy.sh) | 7 | Pull/recreate api+celery+ms from `RELEASE`; health; auto-rollback | Migrate; data wipe |
| [rollback.sh](./rollback.sh) | 7 | Restore previous image pins | Fix data corruption |
| [backup.sh](./backup.sh) | 8 | Postgres dump + optional MinIO mirror + config snapshot | Off-box copy (operator) |
| [restore-pg.sh](./restore-pg.sh) | 8 | Destructive PG restore (`CONFIRM=RESTORE`) | MinIO objects |
| [restore-minio.sh](./restore-minio.sh) | 8 | Mirror backup dir into MinIO (`CONFIRM=RESTORE`) | Postgres |
| [apply-demo-seeds.sh](./apply-demo-seeds.sh) | seeds | Apply `seeds/demo/*.csv` (+ form JSON) into tenant `demo` | Create tenant if missing |

## bootstrap-host.sh

**Target:** Ubuntu 22.04/24.04 LTS (AWS EC2 practice or bare metal).

```bash
# From a clone of this directory on the host:
sudo ./scripts/bootstrap-host.sh

# Or install bundle from another path:
sudo BUNDLE_SRC=/home/ubuntu/lahis-deployment ./scripts/bootstrap-host.sh

# Optional: open 80/443 with ufw (off by default)
sudo CONFIGURE_UFW=1 ./scripts/bootstrap-host.sh

# Skip docker install if already provisioned
sudo INSTALL_DOCKER=0 ./scripts/bootstrap-host.sh
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `DEPLOY_ROOT` | `/opt/lahis` | Deploy bundle location |
| `DATA_ROOT` | `/data` | Persistent data parent |
| `ENV_NAME` | `staging` | Written to `$DEPLOY_ROOT/ENV_NAME` |
| `DEPLOY_USER` | `$SUDO_USER` | Added to `docker` group; owns `$DEPLOY_ROOT` |
| `BUNDLE_SRC` | parent of `scripts/` if it has `compose.yml` | Source tree to rsync into `DEPLOY_ROOT` |
| `INSTALL_DOCKER` | `1` | Install Docker Engine + Compose plugin |
| `CONFIGURE_UFW` | `0` | If `1`, allow OpenSSH + 80 + 443 |

**Idempotent:** re-runs do not overwrite existing `.env` or `RELEASE`.

**After bootstrap:** edit secrets, pin image digests, set DNS — then wait for first-boot step (not this script).

## migrate.sh

Requires compose project files + `.env` in the deploy root. Bring up `db` (and preferably `redis`) first.

```bash
cd /opt/lahis
docker compose up -d db redis
./scripts/migrate.sh --plan    # review
./scripts/migrate.sh           # apply (5s cancel window)
```

Do **not** set `RUN_MIGRATIONS=1` on the long-running `api` service for shared staging.

## bootstrap-minio.sh

```bash
cd /opt/lahis
docker compose up -d minio
./scripts/bootstrap-minio.sh
```

For direct public media URLs, `.env` must use a bucket-qualified
`AWS_S3_CUSTOM_DOMAIN` and `MINIO_PUBLIC_READ=1`; the script creates a sentinel
object that `smoke.sh` fetches through the public proxy. To use private media,
unset `AWS_S3_CUSTOM_DOMAIN` and set `MINIO_PUBLIC_READ=0` instead.

## smoke.sh

```bash
cd /opt/lahis
./scripts/smoke.sh                 # public HTTPS failures = SKIP unless strict
SMOKE_STRICT=1 ./scripts/smoke.sh  # require public DNS/TLS
SKIP_PUBLIC=1 ./scripts/smoke.sh   # compose-only (good before DNS)
```

Full ordered procedure: [../FIRST_BOOT.md](../FIRST_BOOT.md).

## deploy.sh / rollback.sh

```bash
cd /opt/lahis

# Pin digests in RELEASE (or pass explicitly):
./scripts/deploy.sh \
  --api ghcr.io/onehealthtoolkit/ohtk-api@sha256:abc... \
  --ms  public.ecr.aws/g0x0v6d0/lahis-ms@sha256:def...

# Or edit RELEASE then:
./scripts/deploy.sh

# Lab only with floating tags:
ALLOW_LATEST=1 ./scripts/deploy.sh

# Manual rollback:
./scripts/rollback.sh
./scripts/rollback.sh RELEASE.history/RELEASE.20260714T120000Z
```

- Lock: `.deploy.lock`
- Snapshots: `RELEASE.prev`, `RELEASE.history/`
- Log: `deploy.log`
- Health: api `/health`, ms HTTP, celery running (timeout `HEALTH_TIMEOUT`, default 120s)
- Auto-rollback on failed health unless `NO_ROLLBACK=1`

Does **not** run migrations — use `migrate.sh` separately when schema changes.

## backup.sh / restore-pg.sh / restore-minio.sh

```bash
cd /opt/lahis

# Daily-style backup
./scripts/backup.sh
SKIP_MINIO=1 ./scripts/backup.sh
RETAIN_DAYS=7 ./scripts/backup.sh

# Cron (example)
# 15 2 * * * cd /opt/lahis && ./scripts/backup.sh >>/var/log/lahis-backup.log 2>&1

# Restore Postgres (DESTRUCTIVE)
CONFIRM=RESTORE ./scripts/restore-pg.sh /data/backups/pg-YYYYMMDDTHHMMSSZ.sql.gz

# Restore MinIO objects from a backup mirror dir
CONFIRM=RESTORE ./scripts/restore-minio.sh /data/backups/minio-YYYYMMDDTHHMMSSZ
```

Outputs under `/data/backups` by default. **Copy off-box** — on-disk only is not disaster recovery.

Restore scripts refuse to run without `CONFIRM=RESTORE`.

## apply-demo-seeds.sh

Applies Excel-friendly CSVs from [seeds/demo/](../seeds/demo/):

```bash
cd /opt/lahis
./scripts/apply-demo-seeds.sh
# SEEDS_DIR=/opt/lahis/seeds/demo TENANT_SCHEMA=demo ./scripts/apply-demo-seeds.sh
```

Edit CSVs in Excel (UTF-8), re-run to upsert.

## run-integration-smoke.sh

Runs an opt-in staging smoke for signed `report.submitted` delivery, OAuth
client credentials, integration read/write endpoints, and idempotency:

```bash
cd /opt/lahis
./scripts/run-integration-smoke.sh
```

See [integration-smoke/README.md](../integration-smoke/README.md) for the
fixture lifecycle and coverage boundary. It temporarily recreates `api` and
`celery` to load a staging-only webhook signing secret, then recreates them
again without that secret when complete.
