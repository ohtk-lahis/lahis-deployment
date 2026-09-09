# STATUS — LAHIS Admin Train-the-Trainer Guide

North star: [SPEC.md](./SPEC.md)

Update this file at the end of every authoring session. Do not mark `done` without screenshots and a staging check.

Status values: `not-started` | `draft` | `screenshots` | `review` | `done` | `blocked`

| Unit | Part | File | Status | Staging checked | Screenshots | Notes |
|---|---|---|---|---|---|---|
| u00 | 0 | `chapters/00-how-to-use.md` | draft | not-required | none | Drafted. No screenshot required by SPEC; needs human review before `done`. |
| u01 | 1.1 | `chapters/01-what-we-have.md` | draft | 2026-09-08 | 1 authored diagram; sidebar screenshot pending | Live sidebar checked. The workflow diagram is now a vector illustration; Dashboard-sidebar screenshot still needs saving. |
| u02 | 1.2 | `chapters/02-system-map.md` | draft | partial / drift | 4 authored diagrams; Authority screenshot pending | Live `L01` check: `Authorities` showed 0 records, although the demo seed defines the Laos hierarchy. Live role comparison remains pending. |
| u03 | 2.1 | `chapters/03-login.md` | draft | partial | 1 cropped figure | Drafted from the verified `L01` / `Laos` sidebar state. The tenant-selection screen remains uncaptured. |
| u04 | 2.2 | `chapters/04-first-checks.md` | draft | 2026-09-08 | 3 cropped figures | Short live check of Authority hierarchy, Village status/location, and User Authority/Role. |
| u05 | 3 | `chapters/05-user-onboarding.md` | draft | 2026-09-08 | 1 authored diagram + 1 cropped figure | Live creation screen confirms Authority, Role (`Reporter` / `Officer`), From Date and Through Date. |
| u06a | 4.1 | `chapters/06a-form-builder-labels.md` | draft | 2026-09-08 | 8 cropped figures + 1 Mobile example | Live `Animal Sick/Death` confirms the route from `Report Types` through `Definition` → `Form builder` and `Simulator mode`; Dashboard `Reports` → `List` confirms the rendered summary appears in `DATA`; no form data was changed. |
| u06b | 4.2 | `chapters/06b-disease-groups-conditions.md` | draft | 2026-09-08 | 3 cropped figures | Core model and live screenshots confirm that `animal_species` controls separate `suspected_disease` questions through conditions. Do this before u06c. |
| u06c | 4.3 | `chapters/06c-add-species-disease-symptom.md` | draft | 2026-09-08 | 4 reusable crops | Safe recipes drafted for disease, species and symptom changes; practice choices must be reverted. |
| u07 | 5 | `chapters/07-followup-metrics.md` | draft | 2026-09-08 | 1 cropped figure | Live Form builder confirms five follow-up number fields; live Metric accumulation confirms all five use `sum`. No `op` was changed. |
| u08 | 6 | `chapters/08-census-round.md` | draft | 2026-09-08 | 1 authored timeline + 3 cropped figures | Live check confirms Animal census definition is Active/Published, the Production operational round is `DEMO_ANIMAL_2026`, coverage filters, and Census Round Export. `Ensure Defaults` was not pressed. |
| u08b | 7.1 | `chapters/08b-case-workflow.md` | draft | 2026-09-08 | 1 reusable figure | High-level Case narrative; deliberately does not teach operational buttons or state configuration. |
| u08a | 7.2 | `chapters/08a-case-definition.md` | draft | Production + Staging 2026-09-08 | 1 reusable figure; 2 Production crops pending | System Admin governance lesson. Production has 10 rules; Staging has 0. No rule was created or changed. |
| u08c | 7.3 | `chapters/08c-case-close-form.md` | draft | Production + Staging 2026-09-08 | 2 reusable figures; Close-builder crop pending | Covers System Admin close-definition Form Builder design and Officer close data. Production Report Type update currently exposes no close-definition builder, so no configuration was changed. |
| u08d | 7.4 | `chapters/08d-reporter-alerts.md` | draft | Production 2026-09-08; Staging not yet | 1 Production crop; 2 pending | System Admin chapter: automatic message to the original Reporter after Report submission. Production has 18 Animal Sick/Death Alerts. No Alert was changed. |
| u09 | 8 | `chapters/09-daily-work.md` | draft | 2026-09-08 | 7 reusable figures + 4 Mobile offline figures | Officer workflow includes report → follow-up → Officer review, a short Case demonstration, AI Suggest/Ask AI, Risk Level, and the illustrated Offline recovery journey. |
| u12 | Annex | `chapters/12-annex.md` | not-started | | | |
| u13 | Assemble | Google Doc + source chapters | draft | 2026-09-09 | 48 embedded figures | [Online draft](https://docs.google.com/document/d/1fQ5PPBGFqQBeDZBfwNpIxYhvlCGDEjS1WU_erig-j_o/edit) is retained only as a review copy. Rebuild is pending: `BOOK.md` now controls order and `MARKDOWN_CONTRACT.md` controls semantic source blocks, so the next document must be generated from the normalized Markdown and visually reviewed before it replaces or supersedes this draft. |

## Session log

### 2026-09-08 — spec only

- Wrote `SPEC.md` and this file.
- No chapter authored.
- Next unit when authoring starts: `u00` then `u01`.

### 2026-09-08 — u00 draft

- Drafted `chapters/00-how-to-use.md`.
- Screenshot: not required for this introductory unit.
- No staging change or login was needed.
- Next unit: `u01` — what LAHIS has and what this training will use.

### 2026-09-08 — u01 draft

- Drafted `chapters/01-what-we-have.md`, including the locked work-flow diagram and role table.
- Confirmed the LAHIS Demo Dashboard sidebar live as `L01`: Pages, Reports, Settings and Integration menus are present. `Hotspots` is the current staging menu label.
- Screenshot file is pending save; do not mark this unit done yet.

### 2026-09-08 — u02 draft and staging drift

- Drafted `chapters/02-system-map.md` from the demo seed structure.
- Live `L01` staging check opened `Authorities` and showed 0 records, which conflicts with the demo seed hierarchy.
- Do not capture or mark this unit done until the staging data is explained or restored.

### 2026-09-08 — u09 locked insertion

- Added the offline reporter journey to the u09 brief: pending banner → `RESUBMIT` → pending item disappears and report appears in the reporter's list.
- Immediate submit-success message is not sufficient confirmation.

### 2026-09-08 — u03 draft

- Drafted `chapters/03-login.md` from the verified `L01` / `Laos` sidebar state.
- Login and home screenshots still need saving before the unit can be completed.

### 2026-09-08 — u04 draft and live check

- Drafted the first-check content, later consolidated into `chapters/04-first-checks.md`.
- The draft teaches finding and verifying the approved Laos hierarchy without cleaning up unrelated Authority records.
- Live check: `Authorities` loaded 41 rows and supports search; `Villages` loaded 12 rows with columns `CODE`, `NAME`, `AUTHORITY`, `ACTIVE`.
- Detail check: Sangthong Authority shows `Inherits` Vientiane Capital. A Village detail shows linked Authority, Active status, location fields and map.
- The initial Authorities page briefly showed 0 rows before data loaded; it is not a confirmed data-loss issue.
- Screenshots remain pending save.

### 2026-09-08 — u04 Users check

- Added the live Users-list check to the consolidated Chapter 4.
- Screenshot and user-detail check remain pending.

### 2026-09-08 — u05 draft and role check

- Drafted `chapters/05-user-onboarding.md` for Mobile self-registration.
- Live creation screen confirms that an Invitation Code carries an Authority and allows `Reporter` or `Officer` as the role.
- Source check confirms that registration creates the user with the Invitation Code's Authority and role. Village assignment applies to Reporter registrations.
- Officer registration does not expose password setup on the registration screen; the guide now directs the Officer to set a password in Mobile `Profile` after registration, for Dashboard login.
- Screenshot remains pending save; no Invitation Code was created or changed during this check.

### 2026-09-08 — Chapter 4/5 restructure

- Consolidated the short read-and-verify material for Authority, Village, and Users into Chapter 4.
- Moved Invitation Code, Mobile registration, and the Officer password step into Chapter 5 as one user-onboarding procedure.
- Shifted the remaining planned chapter numbers and unit filenames by one to keep the reader-facing sequence consistent.

### 2026-09-08 — u06a draft and live check

- Drafted `chapters/06a-form-builder-labels.md`.
- Live `Animal Sick/Death` check confirms the `Definition` Form builder and its `Simulator mode`.
- The page also contains Followup Definition and Metric accumulation; the draft deliberately defers those to Chapter 7. It now separately teaches `Description Template` and `Follow Up Description Template` as rendered summaries for the first Report and its Follow-up; a crop of those two fields is still needed.
- No form data was changed or saved. Eight cropped figures are saved: Report Type entry, `Definition`/`Form builder`, Section list, Section title, Question/choice labels, system `name`/`value`, Simulator mode, and the Dashboard `Reports` list `DATA` column where the rendered Description Template appears. One existing Mobile-guide image shows the per-Section page and navigation.
- Reordered u06a around the learner journey: Mobile page flow → Form builder → visible wording → field type → validation → summary template → simulator tests. Validation now covers `required`, numeric and image bounds, text length, and allowed past/future date windows.

### 2026-09-08 — u06b draft

- Drafted the disease-group teaching model from the checked demo seed: seven Species groups map to separate Disease questions that all store `suspected_disease` and are shown by a condition on `animal_species`.
- Added three cropped screenshots from the live Form builder and Simulator mode: separate Disease questions, the Cattle/Buffalo question condition, and the resulting Cattle/Buffalo disease list. No form data was saved or changed.

### 2026-09-08 — u06c draft

- Drafted separate safe procedures for adding a disease, a species and a symptom. The chapter uses existing cropped Form builder and Simulator images; no Staging form data was changed.
- Screenshot captures remain pending: Species source values, one Disease condition, and simulator comparison of Cattle and Chicken.

### 2026-09-08 — u07 draft and live check

- Drafted the Follow-up chapter around the distinction between fields in `Followup Definition` and calculation rules in `Metric accumulation (JSON)`.
- Live check confirms five follow-up number fields: `num_household`, `num_total_animal`, `num_sick`, `num_dead`, and `num_recover`; each metric mapping currently uses `sum`.
- Saved one cropped Form builder figure. No form data or `op` value was changed or saved.

### 2026-09-08 — u08 draft and live check

- Drafted the census-round chapter around safe read-and-check work: Census Definition versus Census Round, coverage status, and Excel export.
- Live Staging check found an Active/Published Animal census definition. The Census Rounds list shows `DEMO_ANIMAL`, while the operational Animal Census and Export screens select Production round `DEMO_ANIMAL_2026`; the chapter records both visible labels without changing either.
- Saved three cropped figures: Census Rounds list, Animal Census coverage, and Census Round Export. No census data was entered and `Ensure Defaults` was not pressed.
- Added the submission timeline: before start is `SCHEDULED`; until the due date is on-time; after the due date through the cutoff is `LATE_WINDOW`; after the cutoff the round is `CLOSED`.

### 2026-09-08 — u09 draft

- Drafted the short trainer demonstration chapter rather than duplicating the Mobile guide. It covers registration, Animal Sick/Death, Follow-up with extra counts, Officer review, optional existing Case/Map/Summarized table, and the offline recovery journey.
- Reused two Mobile-guide figures for a submitted report and Dashboard totals. The offline section requires both pending submission disappearance and appearance in the reporter list; the immediate success message is insufficient.
- Added four supplied Mobile screenshots for the complete Offline journey: Home pending banner, pending list while Offline, `RESUBMIT`, and empty pending list after submission.
- Added the missing Officer topics: automatic or manual promotion to Case, automatic or Officer Case closure, the Report Type close form, AI Suggest (`AI suspected`) and `Ask AI`.
- Added Risk Level: external or Officer source, Low/Medium/High/Critical selection, immediate save, and history of earlier assessments.

### 2026-09-08 — u08a Case Definition

- Added a separate System Admin chapter for `Case Definition` and removed automatic-rule authoring from the Officer daily-work chapter.
- Redesigned the chapter after read-only Production review: teach current policy map → reading a rule → Rule design sheet → test plan, rather than free-form condition authoring. Production has 10 rules and Staging has `0 records`; no rule was created, edited, or deleted.

### 2026-09-08 — u08b/u08c Case separation

- Added u08b as a short, conceptual Case Workflow chapter: it tells the Report-to-Case story without teaching operational detail.
- Added u08c as the separate Officer chapter for the close form: `Close case` versus `False positive`, Test result, Stamped out, and safe read-only practice.
- Reduced u09 to the short demonstration of Officer promotion and linked it to the dedicated Case chapters.

### 2026-09-08 — u08c close-definition Form Builder

- Added the Form Builder model for close definitions: Section → Question → Field → validation, attached to Report Type but shown after `Close case` on Dashboard.
- Read-only Production check found no close-definition builder control on the Animal Sick/Death Report Type update screen. The chapter records the controlled technical-change path instead of inventing a click sequence.

### 2026-09-08 — u08d Reporter Alerts

- Added Reporter Alerts as a separate System Admin chapter after read-only Production review. The list contained 18 `Animal Sick/Death` Alerts.
- The chapter separates automatic Reporter Alerts from Officer comments, AI comments, Case Definitions, and Notification Types. It records the first-matching-Alert behavior and requires overlap testing before any change.
- No Production Alert was created, imported, edited, or deleted. The Alert detail crop and Mobile test result remain pending.

### 2026-09-08 — u08d list crop

- Captured a crop of the Production Reporter Alerts list (total, Report Type, Name) and inserted it as Figure 8.4.1. The capture is read-only; no action button was used.

### 2026-09-08 — u03/u04/u05 cropped illustrations

- Saved and inserted the `L01` / `Laos` identity panel for the login check.
- Saved read-only Staging crops of Authority and Village lists, plus the Users column headings. The Village crop deliberately excludes the unused Animal census setting; the Users crop has no user-row data.
- Saved and inserted the blank Invitation Code form showing Authority, dates, Role, and Villages. No form was saved or changed.

### 2026-09-09 — u01 workflow diagram

- Replaced the plain-text workflow with a vector illustration designed for the guide. It preserves the agreed meaning: Map and Reports is a peer branch, not a child of Hotspots.

### 2026-09-09 — u02 system-map diagrams

- Replaced the plain-text diagrams with four vector illustrations: Mobile-to-Dashboard response loop, Staging/Production and common structure, Authority/Village visibility scope, and user roles. These are teaching diagrams; no live data or settings were changed.

### 2026-09-09 — u05 onboarding diagram

- Replaced the plain-text Invitation Code field list with a vector onboarding flow. It distinguishes Reporter from Officer and keeps the Officer `Profile` password step before Dashboard login.

### 2026-09-09 — u08 submission timeline

- Replaced the wide text timeline with a vertical vector timeline so it remains readable in narrow rendered layouts. It preserves the four documented states: `SCHEDULED`, `OPEN`, `LATE WINDOW`, and `CLOSED`.

### 2026-09-09 — u08 census policy decision

- Added the policy decision that precedes scheduling: how many times each village must update census data in a year. The guide links that decision to the number and dates of Census Rounds without prescribing a frequency.

### 2026-09-09 — u09 report classified as test

- Added Officer handling for a Report verified as non-operational data: `Convert to test report`, its scope and effects, and its distinction from Case `False positive`. The documented action is one-way in the current Dashboard, so the guide requires verification before confirmation and escalation if a Case or notification already exists.

### 2026-09-09 — online draft assembled

- Normalized reader-facing chapter numbers so the opening pair is `1.1` / `1.2`, then `2.1` / `2.2`, followed by Parts `3` through `8`.
- Imported the complete reader order as a native Google Doc. Connector readback confirms the title, 1,677 paragraphs, the complete heading ladder, and 48 inline images.
- Added `PUBLISHING.md`: chapter Markdown and approved crops remain the source of truth; the Google Doc is the shared review copy. Sharing remains owner-controlled until a named audience or link-sharing policy is approved.

### 2026-09-09 — source-format normalization

- Added `BOOK.md` as the canonical reader order and chapter-number manifest. The source order deliberately places Case Workflow (7.1) before Case Definition (7.2), regardless of filename order.
- Added `MARKDOWN_CONTRACT.md` for deterministic source blocks and reader-build behavior. Chapter front matter now uses `chapter`, guidance blocks are native headings and lists rather than blockquotes, and visual text flows are semantic lists or tables.
- The existing Google Doc remains a review artifact only. Its list and page-layout behavior must not be repaired as independent source; regenerate from this normalized source before the next visual review.

### 2026-09-09 — reader-content cleanup

- Reviewed all 16 chapter manuscripts and removed author-facing material from the reader body: the internal book-order note, image inventories, screenshot TODO/status rows, and timed workshop scripts.
- Kept asset and verification status in this file rather than in chapters. Added build validation that rejects known editorial headings and TODO phrases if they re-enter reader content.
- Updated the chapter 1.1 curriculum overview to include Case Definition, Reporter Alerts, AI and Risk, and corrected chapter/figure numbering in the Form Builder and daily-work chapters.

## Drift vs SPEC

- **2026-09-08 — Authorities initial load:** `L01` on LAHIS Demo initially showed `0 records`, then loaded 41 rows including Laos and Sangthong. Treat the first value as a loading-state observation, not a confirmed data gap.

## Staging safety

- Practice form edits outstanding: **none**
- Last known-good note: demo seed Animal Sick/Death as of spec date 2026-09-08
