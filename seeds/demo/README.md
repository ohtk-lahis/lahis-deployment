# LAHIS Demo seeds (CSV)

Excel-friendly seed files for the **demo** tenant on a LAHIS one-box stack.

Open any file in Excel / LibreOffice / Google Sheets. Files use **UTF-8 with BOM** so Thai/Lao characters display correctly in Excel.

## Files

| File | Purpose |
|------|---------|
| [authorities.csv](./authorities.csv) | Authority tree: country → แขวง → district |
| [villages.csv](./villages.csv) | Villages (บ้าน) under an authority |
| [invitations.csv](./invitations.csv) | Invitation codes (numeric), optional village scope |
| [users.csv](./users.csv) | Dashboard users (`AuthorityUser`), including superuser flags |
| [superusers.csv](./superusers.csv) | Tenant bootstrap superuser(s) (plain `User`, no authority) |
| [report_categories.csv](./report_categories.csv) | Report type groups (e.g. **Animal**) |
| [report_types.csv](./report_types.csv) | Report types, form JSON paths, and report/follow-up summary templates |
| [forms/](./forms/) | Form definition JSON files referenced by `report_types.csv` |
| [features.csv](./features.csv) | Feature flags in `Configuration` |
| [configurations.csv](./configurations.csv) | Tenant `Configuration` rows (consent HTML, accept text, register flags) |
| [forms/consent-message.html](./forms/consent-message.html) | HTML body for `mobile.consent.msg` |
| [census_defaults.csv](./census_defaults.csv) | Whether to ensure default census definitions |
| [census_rounds.csv](./census_rounds.csv) | Census round definitions + materialize year(s) |

## Hierarchy model

OHTK authorities use **`inherits`** (child points at parent):

```text
Laos (LA)
 └── Vientiane Capital (แขวง) (VTN-CAP)
      └── Sangthong (VTN-SPN)
           └── villages ST-01 … ST-05
```

- `parent_code` empty = root  
- Multiple parents (rare): use `|` in `parent_code` (e.g. `A|B`)  
- `layer` is documentation only (`1_country`, `2_khwaeng`, `3_district`)

## Roles (`users.csv` / `invitations.csv`)

| Code | Meaning |
|------|---------|
| `REP` | Reporter |
| `OFC` | Officer (dashboard) |
| `ADM` | Admin |

## Apply on a running stack

From the deploy host (`/opt/lahis`), with API up and **demo** tenant existing:

```bash
# seeds live in the deploy bundle
./scripts/apply-demo-seeds.sh

# or explicit path
SEEDS_DIR=/opt/lahis/seeds/demo ./scripts/apply-demo-seeds.sh
```

Script behaviour:

1. Applies **features**  
1b. Upserts **configurations** (consent message HTML + accept text; `value_file` supported)
2. Upserts **authorities** (parents first)  
3. Upserts **villages**  
4. Recreates **invitations** for listed codes under each authority (idempotent by code)  
5. Upserts **users** / **superusers** (sets password from CSV)  
6. Upserts **report categories** and **report types** (loads JSON form definitions)  
7. Optionally runs **census defaults** (animal/human definitions)  
8. Upserts **census rounds** and materializes occurrences for listed years  

### Census round date fields

All date columns use annual **`MM-DD`** rules (not full calendar dates):

- `start_date` / `soft_finish_date` / `hard_finish_date` — submission window  
- `census_period_start` / `census_period_end` — reference period for the count  
- Empty `target_authority_code` = nation-wide (all villages)  
- `materialize_from_year` + `materialize_years` create `CensusRoundOccurrence` rows

Requires:

- `docker compose` project healthy  
- Tenant schema `demo`  
- Image with village + census + reports models  

## Edit tips (Excel)

1. Do not remove the header row.  
2. Keep `code` values unique within authorities / villages / invitations.  
3. Invitation `code` must be **numeric** (mobile / product convention).  
4. `village_codes`: one code, or several separated by `|`.  
5. Booleans: `true` / `false` (lowercase preferred).  
6. After editing, save as **CSV UTF-8**.  
7. Re-run `apply-demo-seeds.sh`.  
8. `report_types.csv` → `definition_file` is relative to `seeds/demo/` (e.g. `forms/animal-sick-death-definition.json`).  
9. Empty `authority_codes` on a report type means **all** authorities in the tenant.

## Current demo login (from seeds)

| User | Password | Authority | Notes |
|------|----------|-----------|--------|
| `L01` | `1234` | Laos | **ADM + superuser** (can configure Authorities) |
| `V01` | `1234` | Vientiane Capital | Officer |
| `S01` | `1234` | Sangthong | Officer |
| `lahisadmin` | `1234` | — | plain superuser (lab only; change on shared hosts) |

## Mobile consent (from seeds)

Public GraphQL `configurations` only returns keys starting with `mobile`.

| Key | Source | Purpose |
|-----|--------|---------|
| `mobile.consent.msg` | `forms/consent-message.html` | HTML body (register + post-login consent) |
| `mobile.consent.accept.msg` | `configurations.csv` inline | Checkbox / accept label |

Empty `mobile.consent.msg` hides the register consent UI. After seed, both keys must be present for the full consent flow.

## Demo report types (from seeds)

| Report type | Category | Form |
|-------------|----------|------|
| **Animal Sick/Death** | **Animal** | `forms/animal-sick-death-definition.json` |

## Demo census rounds (from seeds)

| Code | Kind | Window (MM-DD) | Year | Scope |
|------|------|----------------|------|--------|
| `DEMO_ANIMAL` | ANIMAL | 01-01 → 11-30 soft / 12-31 hard | 2026 | Nation-wide |
| `DEMO_HUMAN` | HUMAN | 01-01 → 11-30 soft / 12-31 hard | 2026 | Nation-wide |

Dashboard: https://lahis.ohtk.org/ — server **LAHIS Demo**.

## Capture / refresh from live DB

To regenerate CSVs from a running demo tenant, dump via Django shell or re-export manually; keep demo passwords only in seed CSVs (lab defaults like `1234` only — never export host `.env`, password hashes, or production credentials into git).
