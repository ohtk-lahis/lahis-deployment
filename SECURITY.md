# Security notes for `lahis-deployment`

## Do not commit

| Path | Why |
|------|-----|
| `.env` | Real Django/DB/MinIO/SMTP secrets |
| `RELEASE` / `RELEASE.prev` / `RELEASE.history/` | Host deploy history (pins only are OK in `RELEASE.pins` / `IMAGE_PINS.md`) |
| TLS private keys, SSH keys, keystores | Credentials |
| DB dumps, MinIO backups under `data/` / `backups/` | May contain tenant PII |

Use [`.env.example`](./.env.example) and [`RELEASE.example`](./RELEASE.example) as templates. Host secrets live only on the server (`/opt/lahis/.env`, mode `600`).

## Demo seed passwords

[`seeds/demo/users.csv`](./seeds/demo/users.csv) and [`seeds/demo/superusers.csv`](./seeds/demo/superusers.csv) use **lab-only** passwords (e.g. `1234`). They are intentional for empty staging boots.

- **Not** production credentials.
- Change or disable after any shared/public demo if the host is reachable.
- Never paste real host passwords into these CSVs.

## Image digests

Public ECR/GHCR digests in `IMAGE_PINS.md` / `RELEASE.pins` are not secrets; they pin immutable builds.
