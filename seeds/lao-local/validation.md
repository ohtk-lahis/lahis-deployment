# Corrected-source validation — 2026-10-08

Command:

```sh
/Users/pphetra/projects/opensurveillance/ohtk-api/.venv/bin/python seeds/lao-local/check.py
```

Result: **PASS** — immutable latest seed source SHA verified; **13** recorded changes; initial and followup definitions exactly equal to latest source; both close field constraint objects unchanged; nonnegative-integer, reference-ID and attachment-via-Comments wording checked; all other snapshot workflow/state/flag/authority/config content preserved; 95 choice occurrences; all 11 species select one of seven existing disease branches; every disease value including existing `-PRRS` survives summary rendering; initial/followup Django rendering includes multiple selections, Other/free text, recovered counts, zeros and numeric dates.

The checker uses existing API Python/Django with standalone settings. It reads Git and files only, with no Django project setup/database access, installation or server.

Existing source has a skin symptom containing a comma. This is preserved; the field uses complete selected-key booleans and joined display text, with no option condition. Only species condition values are checked for list-delimiter collisions.

**Not verified by the author:** corrected local apply/idempotence, preservation of database records, actual client sync/preview/save/detail/followup/close, export mapping and Lao linguistic acceptance. Root subsequently reviewed and applied the corrected source; see workspace execution/local-v2-after.json for exact readback and preservation evidence, and local-v2-repeat-apply.txt for idempotence. This does not change the author-only verification boundary above. No author database writes occurred.

Q02/Q03 helpers are implemented under the user’s delegated translation judgment. The unchanged Q04 candidates and corrected helpers await independent review; the author does not self-approve them. Q05–Q07 scope remains unresolved.
