# SPEC — LAHIS Admin Train-the-Trainer Guide

```
status: draft-lock
created: 2026-09-08
audience: LLM authoring sessions + human reviewer
output: Thai workshop guide for the LAHIS system admin who will train trainers in Laos
method: incremental chapters, not one-shot
```

This file is the north star. If chat, memory, or an older outline disagrees with this file, follow this file. If live staging disagrees with a UI step in this file, follow staging and record the drift in `STATUS.md`. Do not silently invent a third version.

Do not write the whole guide in one session. Author one unit, capture that unit's screenshots, update `STATUS.md`, then stop.

---

## 1. What this document is

Working title: **คู่มืออบรมผู้ดูแลระบบ LAHIS (Train the Trainer)**

English name for files: `FAO_LAOS_ADMIN_TOT`

The reader is the **tenant system admin** (`ผู้ดูแลระบบ`). That person will train trainers in Laos. Those trainers will then teach officers and village reporters.

```text
This guide
  → System admin
      → Trainers in Laos
          → Officers (dashboard)
          → Village reporters (mobile)
```

The guide teaches the admin to:

1. Understand what LAHIS has, and what this programme will use.
2. Prepare the tenant (place, people, codes).
3. Edit the Animal Sick/Death form: labels, species, disease groups, symptoms, show/hide conditions.
4. Understand follow-up measurements: accumulate vs replace.
5. Open and watch a census round.
6. Understand Case management, case-close data, and automatic messages sent back to field staff.
7. Demonstrate one daily reporting journey across Mobile and Dashboard.

### 1.1 What this document is not

| Other document | Difference |
|---|---|
| `lahis-deployment/docs/fao-laos-researcher-guide/` | Tester path. Testers must not change settings. |
| Full OHTK admin manual | Too wide. Many menus exist and are out of scope. |
| Server / deploy runbook | Host install, Docker, secrets, and webhooks stay out. |
| Officer or reporter end-user manual | Those come later. This guide only demos enough for trainers to see the flow. |

Do not copy the researcher guide and swap the title. Reuse a flow only when the admin must see the same screen. Rewrite the voice for an admin who **does** change settings.

---

## 2. Locked product decisions

These are locked for v1 of the guide. Change them only by editing this SPEC.

| Decision | Lock |
|---|---|
| Language of prose | Thai |
| UI names in prose | Exact string on the staging screen, in backticks |
| Screenshot language | Whatever `L01` sees after login on staging (today: English UI) |
| Format while drafting | Markdown chapter files |
| Format at the end | One assembled `.md` + `.docx` (same pattern as the researcher guide) |
| Environment for practice and screenshots | LAHIS staging, tenant `LAHIS Demo` |
| Production | One warning box only. No production how-to in v1 |
| Length | Workshop guide, not an encyclopaedia |
| Mobile depth | Short trainer-facing demo in the daily-work unit. No second mobile tester handbook |
| Census form builder | Out of v1 as a structure tool. Warn only if a new report species may also belong on census |
| Human census | Mention in the feature map. No live-round lesson (demo seed has no open human round) |
| Case-close form | A dedicated Case unit. It uses the same Form Definition structure, but is attached to a Report Type and rendered when an Officer closes a Case. |

Open question, still not locked:

- If the admin adds a species on the report form, must the admin also add that species on Animal Census? v1 answer: **warn, do not teach the census builder**.

---

## 3. Staging capture

### 3.1 Hosts and login

Use the **public staging dashboard**, not localhost.

| Item | Value |
|---|---|
| Dashboard | https://lahis.ohtk.org |
| Tenant picker | `LAHIS Demo` (`demo.api.lahis.ohtk.org`) |
| Admin account | `L01` / `1234` (country admin, superuser) |
| Officer accounts (compare only) | `V01` (Vientiane Capital), `S01` (Sangthong) |
| GraphQL (do not screenshot secrets) | https://demo.api.lahis.ohtk.org/graphql/ |

Do **not** log in at `http://localhost:5100` to capture this guide. The JWT cookie is set on the API host. From localhost the cookie is third-party. `tokenAuth` can succeed and `me` can still fail.

If the browser shows **Unable to load current user profile** or `me` has no `Cookie: JWT=...`, stop. Report the cookie problem. Do not invent screenshots.

### 3.2 Screenshot rules

- Capture from live staging for every dashboard figure in the unit you are authoring.
- Save files under `lahis-deployment/docs/fao-laos-admin-tot/screenshots/`.
- Name files by unit, not a global 01, 02 sequence:

  `c05b-02-disease-condition.jpg`

- Prefer `.jpg` for dashboard. `.png` is allowed for UI with small text if jpg is unreadable.
- Desktop viewport: at least 1280 px wide.
- Crop to the teaching point. Do not paste a huge unreadable full page unless the lesson is layout (home screen).
- Hide or avoid: passwords, integration client secrets, tokens, personal data.
- Caption pattern in Thai:

  `*ภาพที่ {unit}.{n} — {what the reader must notice}*`

- Alt text (markdown image title) describes the screen in Thai.
- Do not reuse a researcher-guide screenshot until you open the same screen on staging and confirm it still matches. If it matches, you may copy the file into this folder with a new `cXX-` name. Prefer a fresh capture.

### 3.3 Staging safety

Staging is shared with researchers. Authoring must not leave the demo tenant broken.

Allowed:

- View, search, filter, open Form builder, use Form simulator.
- Log in as `L01`, `V01`, `S01` to compare menus.

Allowed only with revert in the same session:

- Add a clearly marked practice choice, for example label `TEST_TOT_DO_NOT_KEEP`.
- After the screenshot, delete that choice and save.
- Confirm the published Animal Sick/Death form is back to the seed list.

Never:

- Delete authorities, villages, users, or invitation codes.
- Change field **names** such as `animal_species` or `suspected_disease`.
- Change Metric accumulation `op` on the live animal type and leave it.
- Edit Integration Clients, Webhook Endpoints, or secrets.
- Publish a half-edited form.
- Use real personal data.

If a revert fails, write a blocker in `STATUS.md` and tell the human before any other unit starts.

### 3.4 Mobile screenshots

Dashboard figures are mandatory live captures.

Mobile figures in the daily-work unit:

1. Try a live capture if a device or emulator is available.
2. If not, reuse a researcher-guide mobile screenshot only after you state that reuse in the chapter and in `STATUS.md`.
3. Do not draw fake phone UI.

---

## 4. Output layout

```text
lahis-deployment/docs/fao-laos-admin-tot/
  SPEC.md                 ← this north star
  STATUS.md               ← unit progress; update every session
  chapters/               ← one file per unit; Thai prose
  screenshots/            ← c{unit}-{nn}-{slug}.jpg
  FAO_LAOS_ADMIN_TOT.md   ← assembled at the end only
  FAO_LAOS_ADMIN_TOT.docx ← assembled at the end only
```

Do not create the assembled `.md` / `.docx` until every reader-facing unit is `done` or the human asks for a partial bind.

Sibling reference (read, do not overwrite):

- `lahis-deployment/docs/fao-laos-researcher-guide/`

Seed reference for lists and codes:

- `lahis-deployment/seeds/demo/` especially `users.csv`, `invitations.csv`, `villages.csv`, `forms/animal-sick-death-definition.json`, `forms/animal-sick-death-followup-definition.json`, `forms/animal-metric-accumulation.json`

---

## 5. Reader-facing outline

Keep these part numbers in the assembled guide. Units below may split a part across sessions.

| Part | Title | Authoring units |
|---|---|---|
| 0 | How to use this document | `u00` |
| 1 | LAHIS overview and system map | `u01` `u02` |
| 2 | Access and first checks | `u03` `u04` |
| 3 | Prepare new users | `u05` |
| 4 | Report form and rendered summaries | `u06a` `u06b` `u06c` |
| 5 | Follow-up form and how numbers combine | `u07` |
| 6 | Census round | `u08` |
| 7 | Case management and automatic response | `u08b` `u08a` `u08c` `u08d` |
| 8 | Daily work that trainers must see | `u09` |
| Annex | Accounts, menu map, checklist, word list | `u12` |
| — | Assemble md + docx | `u13` (not reader-facing) |

---

## 6. Authoring units (incremental)

Author **one unit per session** unless the human names more. A unit is done only when prose, screenshots, and `STATUS.md` are updated.

### Shared chapter shape

Each `chapters/*.md` file must have:

1. YAML-like header: `unit`, `part`, `title`, `status`, `staging_checked`.
2. One-paragraph purpose for the admin reader.
3. Numbered steps (one action per step).
4. Screenshots next to the step they prove.
5. A **Do / Do not** box where the admin can break the tenant.
6. A **Trainer talking points** box (what to say when teaching trainers). Short. Five bullets or fewer.
7. A **Check** table: what the trainee must be able to do after this unit.

Write Thai STE-like prose for the reader: short sentences, one fact per sentence, condition before action, no idioms. Keep menu names and field names in backticks as they appear on staging.

Do not start a unit with a stable ID code. Thing first.

---

### `u00` — How to use this document

File: `chapters/00-how-to-use.md`

Teach:

- Who the reader is, and who the reader will train.
- Staging vs production.
- How to read UI names in backticks.
- How to stop if the site is the wrong environment.

Screenshots: none required, or one title/login hero if useful.

---

### `u01` — What the system has, and what this training will use

File: `chapters/01-what-we-have.md`

This unit is conceptual. It must appear before any admin recipe.

**Picture of the work** (keep this diagram):

```text
Village + Reporter
        │
        ├── Census     periodic count of animals in the village
        │
        └── Report     one sick/death event
                ├── Follow-up
                ├── Risk and AI comment
                ├── Case   (officer opens and closes)
                └── Cluster (related events)
                        │
                        └── Map, summarized table, Excel export
```

**What LAHIS has** (include Form builder and follow-up metrics):

| Feature | Meaning |
|---|---|
| Place and people | Staging/Production, authority, village, users, invitation codes |
| Animal census | Periodic village count of households and animals |
| Human census | Form exists. No open round in the current demo set |
| Animal sick/death report | One event of sick or dead animals |
| Follow-up | Later counts on the same report |
| Follow-up metrics | Each count accumulates or replaces |
| Form builder | Labels, species, disease groups, symptoms, show/hide |
| Case | Officer work after a report needs follow-through |
| Risk | Risk level on a report |
| AI comment | First analysis from an external service |
| Cluster | Group of related reports |
| Map and export | See events and download tables |

**What this training will use**

Use and teach:

- Place and people
- Animal census (open round, coverage, export — not census form authoring)
- Animal sick/death report and follow-up
- Form builder: labels, species, disease groups, symptoms, show/hide
- Follow-up accumulate vs replace
- Case, map, summarized table, census export (short demo)

See, then explain. Do not configure:

- Risk result, AI comment, Cluster result
- Integration menus

Do not use in this training:

- Observation
- Outbreak plans
- State definition and case definition
- Integration clients, secrets, webhooks
- Census form builder as a structure tool
- Human census as a live round

**Who uses each feature** — keep a role table (Admin / Trainer / Officer / Reporter).

Screenshot: home/sidebar overview on staging, annotated in caption as “more menus exist than this training will use”.

---

### `u02` — System map

File: `chapters/02-system-map.md`

Teach:

- Dashboard vs mobile.
- Staging vs Production, authority, village vs user. Explain `Tenant` only when it appears as a UI label.
- Roles: Admin (`ADM`), Officer (`OFC`), Reporter (`REP`).
- Authority tree used in demo:

```text
Laos (LA)
 └── Vientiane Capital (VTN-CAP)
      └── Sangthong (VTN-SPN)
           └── villages ST-01 … ST-05
```

- `L01` sees more Settings menus than `V01` / `S01`.

Screenshot: Authorities list; optional Users list showing roles.

---

### `u03` — Login and first checks

File: `chapters/03-login.md`

Steps: open https://lahis.ohtk.org → select `LAHIS Demo` → sign in as `L01` → confirm username and authority `Laos` at the bottom of the sidebar.

Stop if: wrong tenant, site down, production data, or profile fails to load.

Screenshots: login + tenant picker; home after login with username visible.

---

### `u04` — First checks: authorities, villages, and users

File: `chapters/04-first-checks.md`

Teach: open and verify an existing authority, village, and dashboard user. Keep this short unit read-and-verify only: hierarchy, village location/status, user Authority and Role.

Do not delete demo rows. For screenshots, open existing Sangthong villages.

---

### `u05` — Prepare new users with Invitation Code

File: `chapters/05-user-onboarding.md`

Teach: create or read an Invitation Code that pre-sets Authority and role for Mobile registration. Cover both a village-scoped `Reporter` code and an `Officer` code for city-level staff; check from/through dates before sharing the code. After Officer registration, set a password in Mobile `Profile` for Dashboard login.

Do not reset `L01` / `V01` / `S01` passwords except to the known demo value if already `1234`.

Demo codes exist (see researcher guide / `invitations.csv`). Prefer showing an existing code. Creating a new code is allowed if you leave it valid and record the code in `STATUS.md`.

---

### `u06a` — Form builder and labels

File: `chapters/06a-form-builder-labels.md`

Path: Settings → `Report Types` → `Animal Sick/Death` → Form builder on **Definition**.

Teach: Section as one Mobile page; section title, question title, description, choice **label**; field **type** and validation (`required`, bounds, and allowed date window). Also teach `Description Template` for the first Report and `Follow Up Description Template` for Follow-up: these render a one-line summary from stored fields and are not Form Definition fields.

Hard rule: do not change field **name**. For a label-only change, keep the stored choice **value**, `type`, and `condition` the same. Templates may depend on these stable names. Change validation only against an approved data rule, then test its boundary in the simulator.

Use Form simulator to prove the new words. Revert practice label changes unless the human asked to keep them.

---

### `u06b` — Disease groups and show/hide

File: `chapters/06b-disease-groups-conditions.md`

This is the core concept unit. The admin must learn this before adding species or diseases.

**Locked teaching model** (from current staging seed):

Disease is not one list. One Species question. Several Disease questions. All Disease questions store `suspected_disease`. Each has a condition on `animal_species`.

```text
Species (animal_species)
    ├── Cattle, Buffalo  → Disease list  condition in  "Cattle, Buffalo"
    ├── Sheep, Goat      → Disease list  condition in  "Sheep, Goat"
    ├── Pig              → Disease list  condition in  "Pig"
    ├── Dog, Cat         → Disease list  condition in  "Dog, Cat"
    ├── Chicken          → Disease list  condition =   "Chicken"
    ├── Goose, Duck      → Disease list  condition in  "Goose, Duck"
    └── Other            → Disease list  condition =   "Other"
```

Condition fields in Form builder:

| Field | Meaning | Must match |
|---|---|---|
| Name | Which answer the rule reads | `animal_species` |
| Operator | How to match | `in` or `=` |
| Value | Species **value** | Exact value string, not only the Thai/Lao label |

Symptoms are different: body-system groups, usually always shown.

Screenshots: Species question; one Disease question with its condition panel open; Form simulator switching Cattle vs Chicken to show different lists.

Do not put one species in two disease groups.

---

### `u06c` — Add species, disease, symptom

File: `chapters/06c-add-species-disease-symptom.md`

Recipes:

**Add a disease**

1. Open the disease group for that species.
2. Add a choice. Set label and value.
3. Keep `I cannot determine the disease` at the end.
4. Simulator: select that species, confirm the new disease appears.
5. Revert the practice disease unless the human asked to keep it.

**Add a species**

1. Add the species on the Species question (label + value).
2. Decide which disease group owns it.
3. If an existing group fits, add the species **value** to that condition (`in` list).
4. If no group fits, copy a Disease question and set a new condition.
5. Simulator: new species shows the right list; old species still show old lists.
6. Warn: Animal Census may need the same species later. Do not open census builder in this unit.
7. Revert the practice species and condition.

**Add a symptom**

1. Open the matching body-system question (for example Digestive System).
2. Add a choice.
3. Simulator. Revert.

Trainer talking points must include: “Change the list, then test with the species that owns that list.”

---

### `u07` — Follow-up form and how numbers combine

File: `chapters/07-followup-metrics.md`

Path: same Report Type. Two controls:

1. **Followup Definition** (Form builder) — fields people fill.
2. **Metric accumulation (JSON)** — how numbers combine. Form builder does **not** set this.

Locked table:

| Nature | What the user enters | Total the system shows | `op` |
|---|---|---|---|
| Accumulate | Extra count for this visit | First report + every follow-up | `sum` |
| Replace | Current total now | Last follow-up, or first report if none | `latest` |

Current LAHIS animal seed: **all five counts accumulate** (`sum`):

`num_household`, `num_total_animal`, `num_sick`, `num_dead`, `num_recover`

Worked example (keep these numbers):

| Count | First report | Follow-up | Shown total |
|---|---:|---:|---:|
| Sick | 2 | 1 | 3 |

If the user enters `3` while `sum` is on, the system shows `5`. That total is wrong.

If the admin adds a new number field on follow-up, the admin must add it to Metric accumulation and choose `sum` or `latest` before trainers use the form.

Do not change live `op` values on staging. Screenshot the JSON as read-only unless you revert.

Practice: submit or inspect an existing follow-up on staging; show `Totals (report + follow-ups)` on dashboard. Prefer an existing demo report over creating many new ones.

---

### `u08` — Prepare a census round

File: `chapters/08-census-round.md`

Teach: Census Definition vs Census Round; Production round `DEMO_ANIMAL_2026`; coverage (submitted / missing / late); Census Round Export.

Do not teach census form authoring. Do not press **Ensure Defaults** unless the human asks.

Screenshot: Census Rounds list; Animal Census coverage; export menu.

---

### `u08a` — Case Definition: automatic Case rule

File: `chapters/08a-case-definition.md`

Admin governance lesson. Teach the distinction between the policy owner, System Admin who implements an approved automatic rule, and an Officer who works on a Case or uses `Promote to case` manually.

Start from the current Production policy map, then teach how to read a rule (`Report Type` → `Description` → `Condition`), prepare a Rule design sheet, and test matching / non-matching / boundary reports before a change is approved. Do not teach free-form condition authoring to Officer or general workshop participants.

Do not teach Case State Definition authoring, integration setup, or bulk import. Do not create or change a live rule merely to obtain a screenshot.

---

### `u08b` — Case Workflow overview

File: `chapters/08b-case-workflow.md`

Tell the story only: Report becomes Case automatically or by Officer, is followed up, then ends as `Close case`, `False positive`, or `Automatic close`. Keep the chapter at the conceptual level; link to u08a for rules, u08c for the close form, and u09 for Officer work.

---

### `u08c` — Case close form

File: `chapters/08c-case-close-form.md`

Teach the close-definition Form Builder as a System Admin responsibility, then the Officer-facing data required when a real Case is closed. Explain that the form is attached to Report Type but renders in the Dashboard after `Close case`; cover Section / Question / Field / field type / `required` / validation / stable field name. Teach `Close case` versus `False positive`; the Animal Sick/Death fields `Test result` and `Stamped out`; data belongs to Case, not the original Report; and safe read-only practice. State that Officer cannot change the form structure. If the Dashboard has no close-definition builder, record the gap and use the controlled technical-change path rather than inventing clicks.

---

### `u08d` — Reporter Alerts: automatic message to the reporter

File: `chapters/08d-reporter-alerts.md`

Teach Reporter Alerts as a System Admin configuration that sends one automatic message to the reporter after a submitted Report matches a condition. Clearly distinguish it from Officer comments, AI comments, Case Definition, and Notification Types. Cover the configuration map: Report Type, Name, Condition, Title Template, and Body Template. Officer and Reporter cannot create or edit the Alert.

Start from the read-only Production list: 18 Alerts were present for `Animal Sick/Death` on 8 September 2026. Do not add, import, edit, or delete an Alert on Production. Explain that current processing sends the first matching Alert only; therefore overlapping conditions must be reviewed and tested. Use a policy/design sheet and matching, non-matching, and overlap tests in a controlled environment. Do not teach free-form condition syntax to general participants.

---

### `u09` — Daily work that trainers must see

File: `chapters/09-daily-work.md`

Short demo, not a second researcher guide. Goal: the admin can walk trainers through one happy path.

Include, each in a few steps:

1. Reporter registers with a village code (mobile).
2. Submit Animal Sick/Death.
3. Add a follow-up using **extra** counts.
4. Officer views the report; mention Risk / AI if they appear; do not configure integration.
5. Optional: promote to case and show close (officer), map, summarized table. Automatic Case rules belong to Chapter 7.2.
6. If a report was recorded without internet: show the pending-submissions banner, choose `RESUBMIT` once internet returns, then confirm that the pending item disappears and the report appears in the reporter's list. The immediate submit-success message alone is not proof.

Keep this unit thin. Point to the researcher guide for extra tester detail if needed.

---

### `u12` — Annex

File: `chapters/12-annex.md`

- Demo accounts and Sangthong villages / invitation codes (copy from staging, not from memory).
- Menu map: in scope / see-only / out of scope.
- Short word list Thai / English / Lao for: staging, production, authority, village, report, follow-up, census, accumulate, replace, condition. Keep it short.

---

### `u13` — Assemble (last)

Only after reader-facing units are `done` or the human asks.

1. Concatenate chapters in outline order into `FAO_LAOS_ADMIN_TOT.md`.
2. Renumber nothing if captions already use `{unit}.{n}`. Keep those IDs.
3. Build `.docx` with the same screenshot files (follow the `docx` skill when that session runs).
4. Spot-check: every image path resolves; login URL is staging; no integration secrets.

---

## 7. Source of truth order

When facts conflict, use this order:

1. This `SPEC.md`
2. Live staging UI at https://lahis.ohtk.org (tenant `LAHIS Demo`)
3. Demo seeds under `lahis-deployment/seeds/demo/`
4. Researcher guide (flows and sample data only)
5. FAO-feature wiki contracts and decisions
6. Chat history

If (2) disagrees with (1) on a **button label or layout**, follow (2) and add a drift note in `STATUS.md`. If (2) disagrees with (1) on **scope** (for example a new menu appears), do not expand scope. Stay on the locked outline.

---

## 8. Session protocol (mandatory)

Paste this into an authoring session, then add the unit id.

```text
Read:
  lahis-deployment/docs/fao-laos-admin-tot/SPEC.md
  lahis-deployment/docs/fao-laos-admin-tot/STATUS.md

Author only unit: <UNIT_ID>
Do not author other units.
Do not assemble md/docx.

Steps:
1. Confirm STATUS for that unit is not `done`.
2. Log in to https://lahis.ohtk.org as L01 on LAHIS Demo.
3. Walk the live screens for this unit.
4. Write or update chapters/<file>.md in Thai.
5. Capture screenshots into screenshots/c<unit>-*.jpg.
6. Revert any practice form edits.
7. Fill the chapter Check table against what you actually did.
8. Update STATUS.md (status, screenshots, drift, next).
9. Stop.
```

### Session done criteria

A unit may move to `done` only if all of these are true:

- Chapter file exists and matches the locked teaching model for that unit.
- Required screenshots exist on disk and are referenced in the chapter.
- Staging was opened in this session (`staging_checked: yes`).
- Practice edits reverted, or the human accepted a keep.
- `STATUS.md` row updated.
- No secrets in screenshots or prose.

A unit that has prose but no screenshots is `draft`, not `done`.

---

## 9. Style rules for the Thai guide

- Short sentences. One fact or one instruction per sentence.
- Numbered steps. Condition before action: `If X fails, do Y.`
- Active voice. Use `must` or an imperative. Do not use `should`.
- Keep articles in English glosses. In Thai, keep sentences complete.
- Do not quiz the reader with internal codes (`D09`, `RF3`). If a seed list is needed, describe the list.
- Call the reader `ผู้ดูแลระบบ` or `คุณ`. Call the next audience `วิทยากร` (trainer).
- Distinguish **label** (คำที่ผู้ใช้เห็น) and **value** (ค่าที่ระบบเก็บ).
- Distinguish **accumulate** (บวกเพิ่ม) and **replace** (แทนที่ยอด).

Mirror the researcher guide's figure caption style, not its tester voice.

---

## 10. Out of scope forever unless SPEC changes

- Observation
- Outbreak plans
- Places as a master-data lesson
- Case state definition authoring
- Integration client creation, webhook URL, secrets
- Server deploy, Docker, backups
- Form JSON hand-editing as the primary method
- Changing field names
- Putting a species in two disease groups
- Teaching census schema builder
- One-shot generation of all chapters

---

## 11. Human review gates

After each unit, the human reviews:

1. Is the teaching point correct on staging?
2. Are screenshots readable and current?
3. Did the session leave staging clean?
4. May the next unit start?

Do not start `u06c` before `u06b` is `done`. Do not start `u07` before `u06a` exists (follow-up sits on the same Report Type screen). `u01` should exist before `u04` so later chapters can point back to the feature map.
