# Lao report configuration — latest seed reconciliation

Runtime source: **`../tot/report-setup.json`**. This directory contains review evidence and offline checks only; there is no parallel form-definition seed or CSV to apply.

The user corrected the source selection: use the latest seed, which had not been deployed locally. The candidate imports `seeds/tot/report-setup.json` from deployment revision **34726938eb1ad88f2a3a2e5a40c0a88f93cd4cce**, source SHA256 **0dfcefc9f784ce81beea52ec76ced1d2ad294e286350e88fce0ebbe35b93cf61**. See `source.json`. Both initial and followup definitions are preserved **exactly**, including all 95 Lao option occurrences, seven species conditions, sections, field IDs, constraints and existing wording. The former demo-derived candidate is superseded and its duplicate runtime forms/CSVs removed.

User subsequently authorized translation corrections: “ถ้าคิดว่าคนทำ slice แปลผิด ให้ปรับคำได้เลย”. The two Q02/Q03 helper proposals are now implemented; existing Q04 candidates remain unchanged for independent review under that authorization. Q05–Q07 remain unresolved.

Specification remains `FAO-feature/expectations/lao-language-2026-10-08/expectation-specification.md`. Latest seed content supplies the definitions; existing wording is not automatically linguistically approved. The source snapshot's `source` and `captured_on` metadata remain unchanged to preserve provenance, not to imply current staging verification.

## Delta from latest seed

| Property | Changes | Expectation |
| --- | ---: | --- |
| ReportType name | 1 | M01 / D02 exact M01 PPT pair |
| Initial / followup definitions | **0** | Already contain M02/M03/M05 PPT pairs; preserve latest seed |
| Metric labels | 5 | M06 / D01, proposed shared labels using existing five-count wording |
| Close question labels | 2 | D04 / D05 exact PPT labels |
| Close question helpers | 2 | Q02 / Q03 corrected under delegated translation judgment; independent review pending |
| Initial / followup templates | 2 | M04 / M06, proposed Lao summary prose |
| Existing export selector Configuration key | 1 addition | CFG-01 rename dependency |
| Close audit messages Configuration | 1 addition | User-approved seven-message JSON bundle |
| States, category, flags, authority codes, other configurations | **0** | Preserved in full snapshot and ignored by scoped apply |

`property-diff.json` records all 14 changes against the immutable latest source. `value-dependencies.json` lists every preserved option at its exact path. `dependency-matrix.md` records conditions/templates/consumers. `unchanged-text.json` lists remaining English definition text without declaring whole-form completion.

Templates retain selected species/disease/age/sex/symptoms and user text. Initial summary adds recovered animals and Other text; both templates display zero counts/households to meet A03 data completeness. Stored numeric semantics and metric formulas are unchanged. Missing optional numbers retain the existing zero-display convention. User text is escaped by Django and never translated. Incident date uses proposed numeric `dd/mm/yyyy` with a Lao prefix. Photos remain in their existing client flow.

## Scoped local apply

Do not use the full setup importer for this localization apply. The scoped script reads the existing report-setup format but selects only seven fields: name, definition, followup_definition, metric_accumulation, close_definition, renderer_data_template and renderer_followup_data_template. It also selects exactly `cases.lahis_summarized_report_type_name` and `cases.close_audit_messages`. Every other snapshot section/property is ignored for writes.

From the existing local `ohtk-api` shell:

```python
# DB_NAME=ohtk_staging_poc_20260505 .venv/bin/python manage.py shell
import runpy
apply_config = runpy.run_path('/Users/pphetra/projects/opensurveillance/.worktrees/lao-seed-local/scripts/apply-report-configuration.py')['main']
args = ['--seed-dir', '/Users/pphetra/projects/opensurveillance/.worktrees/lao-seed-local/seeds/tot',
        '--tenant', 'lahis', '--report-type-id', '91a6bdac-c54f-418c-a43d-8490a33e0705']
apply_config(args)  # preview only
# After reviewing database/schema/id and the full diff:
apply_config(args + ['--apply', '--expected-preview', 'SHA256_FROM_REVIEWED_PREVIEW'])
apply_config(args)  # expected no diff; a repeat apply with this fresh hash is a no-op
```

The UUID and local tenant were verified by root. No name-based creation occurs. Existing authority links, category, workflow and flags remain untouched. Updated report configuration changes `updated_at` for mobile sync; a no-op does not. Existing reports/followups are never resaved. The preview hash guards database, schema, current report fields and authority IDs, selector value and proposed configuration. Any change requires a fresh preview.

For fresh setup, use the established setup path to create the intended report type first, then its verified UUID for this scoped apply. Empty provisioning is not tested here. Root owns database application and old-record preservation checks; the author made no database writes. Root subsequently applied this corrected latest-seed candidate after independent review. The v2 readback equals the candidate; repeat apply makes no changes. ReportType identity/count, 41 authority links and all existing incident/followup row fingerprints are preserved. See workspace `FAO-feature/plans-wip/lao-language-2026-10-08/execution/local-v2-after.json` and `local-v2-repeat-apply.txt`; earlier unversioned local evidence is superseded.

## Verification

```sh
/Users/pphetra/projects/opensurveillance/ohtk-api/.venv/bin/python seeds/lao-local/check.py
```

The check reads the immutable source via Git, verifies its SHA, proves exact definition preservation and the 13-property delta, then renders templates using current source values. `validation.md` records results. Root verified local config apply/readback/idempotence. Client sync/UI, persisted new-report flows and live export remain unverified; API main consumer contract checks are recorded separately in execution/api-handoff.md. Lao linguistic acceptance remains separate.

## V3 local application

Root applied the two reviewed Q02/Q03 helper corrections under user-delegated translation judgment. Exact candidate readback, unchanged UUID/count/41 authorities and all report-row fingerprints, and repeat no-op verified in workspace execution/local-v3-verification.json. Earlier v2 evidence still proves corrected latest-definition import. Runtime UI remains unverified; Q05–Q07 scope is pending.

V4 supersedes only the Q02 helper with plain language for villagers: count animals of this species destroyed; enter0 if none. Independent source review passed. Root applied and verified unchanged constraints/data plus no-op repeat in execution/local-v4-verification.json.

## Close audit message bundle — approved 8 October 2026

`cases.close_audit_messages` stores one JSON object as the Configuration text value. Keys: `close_case`, `false_positive`, `automatic_close`, `complete_after_auto_close`, `superuser_edit`, `no_close_data`, `reason`. This tenant seed supplies Lao text directly; there is no locale nesting or template syntax. The API uses English for missing/blank/non-string entries and logs/falls back to the full English set for malformed JSON or a non-object value. Unknown keys are ignored. The scoped importer requires all seven nonempty strings in this reviewed seed and guards both configuration rows, including soft-delete state, in its preview digest.

Payload field labels come from close_definition (field label, then question label; legacy field labels supported). Unknown labels retain humanized-key fallback. False-positive reason uses the configured reason label. User values are not translated. Only newly created audit comments use this configuration; stored comments are untouched. No API schema/client/generated change or migration is required.
