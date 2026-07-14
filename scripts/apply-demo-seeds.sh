#!/usr/bin/env bash
# Apply CSV seeds from seeds/demo into the demo tenant schema.
#
# Usage (on deploy host, from /opt/lahis):
#   ./scripts/apply-demo-seeds.sh
#   SEEDS_DIR=/opt/lahis/seeds/demo TENANT_SCHEMA=demo ./scripts/apply-demo-seeds.sh
#
# Requires: running api container, PostGIS, demo tenant already created.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

SEEDS_DIR="${SEEDS_DIR:-${ROOT}/seeds/demo}"
TENANT_SCHEMA="${TENANT_SCHEMA:-demo}"

if [[ ! -d "${SEEDS_DIR}" ]]; then
  echo "ERROR: seeds dir not found: ${SEEDS_DIR}" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
[[ -f RELEASE ]] && . ./RELEASE
set +a
export IMAGE_API IMAGE_MS

echo "Applying seeds from ${SEEDS_DIR} → tenant schema ${TENANT_SCHEMA}"

# Copy seeds into a temp path the api container can read via stdin + python
# We pass CSV content through environment file mount: bind-mount seeds dir
docker compose run --rm --no-deps \
  -v "${SEEDS_DIR}:/seeds:ro" \
  -e SEEDS_DIR=/seeds \
  -e TENANT_SCHEMA="${TENANT_SCHEMA}" \
  --entrypoint python \
  api manage.py shell <<'PY'
import csv
import json
import os
from pathlib import Path
from datetime import timedelta

from django.utils.timezone import now
from django.contrib.gis.geos import Point
from django_tenants.utils import tenant_context

from tenants.models import Client
from accounts.models import (
    Authority,
    Village,
    InvitationCode,
    AuthorityUser,
    Configuration,
    User,
)
from accounts.village_capability import set_village_capability_enabled
from census.animal_census_capability import set_animal_census_capability_enabled
from census.census_definition_defaults import ensure_default_census_setup
from reports.models import Category, ReportType
from census.models import CensusRoundDefinition
from census.rounds import materialize_occurrences, validate_round_definition

seeds = Path(os.environ["SEEDS_DIR"])
schema = os.environ.get("TENANT_SCHEMA", "demo")


def read_csv(name):
    path = seeds / name
    if not path.exists():
        print(f"skip missing {name}")
        return []
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def truthy(v, default=False):
    if v is None or str(v).strip() == "":
        return default
    return str(v).strip().lower() in {"1", "true", "yes", "y", "on", "enable"}


client = Client.objects.filter(schema_name=schema).first()
if not client:
    raise SystemExit(f"tenant schema '{schema}' not found")

with tenant_context(client):
    # --- features ---
    for row in read_csv("features.csv"):
        key = (row.get("key") or "").strip()
        value = (row.get("value") or "").strip()
        if not key:
            continue
        if key == "features.village_enabled":
            set_village_capability_enabled(truthy(value) or value == "enable")
        elif key == "features.animal_census_enabled":
            set_animal_census_capability_enabled(truthy(value) or value == "enable")
        else:
            obj = Configuration._base_manager.filter(key=key).first()
            if obj:
                obj.value = value
                obj.deleted_at = None
                obj.save()
            else:
                Configuration.objects.create(key=key, value=value)
        print("feature", key, value)

    # --- authorities (parents first: CSV should be ordered; also multi-pass) ---
    rows = read_csv("authorities.csv")
    by_code = {}
    pending = list(rows)
    safety = 0
    while pending and safety < 20:
        safety += 1
        next_pending = []
        for row in pending:
            code = (row.get("code") or "").strip()
            name = (row.get("name") or "").strip()
            parent_raw = (row.get("parent_code") or "").strip()
            if not code or not name:
                continue
            parents = [p for p in parent_raw.split("|") if p.strip()]
            missing = [p for p in parents if p not in by_code and not Authority.objects.filter(code=p).exists()]
            if missing:
                next_pending.append(row)
                continue
            auth, created = Authority.objects.get_or_create(code=code, defaults={"name": name})
            if not created and auth.name != name:
                auth.name = name
                auth.save(update_fields=["name", "updated_at"])
            parent_objs = []
            for p in parents:
                if p in by_code:
                    parent_objs.append(by_code[p])
                else:
                    parent_objs.append(Authority.objects.get(code=p))
            auth.inherits.set(parent_objs)
            by_code[code] = auth
            print(("created" if created else "updated"), "authority", code, name, "parents", parents)
        if len(next_pending) == len(pending):
            raise SystemExit(f"unresolved authority parents: {[r.get('code') for r in pending]}")
        pending = next_pending

    # --- villages ---
    for row in read_csv("villages.csv"):
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()
        acode = (row.get("authority_code") or "").strip()
        if not code or not name or not acode:
            continue
        auth = Authority.objects.get(code=acode)
        lon = (row.get("longitude") or "").strip()
        lat = (row.get("latitude") or "").strip()
        loc = None
        if lon and lat:
            loc = Point(float(lon), float(lat), srid=4326)
        v, created = Village.objects.get_or_create(
            authority=auth,
            code=code,
            defaults={"name": name, "location": loc, "active": truthy(row.get("active"), True)},
        )
        if not created:
            v.name = name
            v.active = truthy(row.get("active"), True)
            if loc:
                v.location = loc
            v.save()
        print(("created" if created else "updated"), "village", code, name, "->", acode)

    # --- invitations ---
    for row in read_csv("invitations.csv"):
        code = (row.get("code") or "").strip()
        acode = (row.get("authority_code") or "").strip()
        role = (row.get("role") or "REP").strip() or "REP"
        if not code or not acode:
            continue
        auth = Authority.objects.get(code=acode)
        days = int((row.get("valid_days") or "365").strip() or "365")
        start = now()
        end = start + timedelta(days=days)
        inv, created = InvitationCode.objects.get_or_create(
            code=code,
            defaults={
                "authority": auth,
                "role": role,
                "from_date": start,
                "through_date": end,
            },
        )
        if not created:
            inv.authority = auth
            inv.role = role
            inv.from_date = start
            inv.through_date = end
            inv.save()
        vcodes = [c.strip() for c in (row.get("village_codes") or "").split("|") if c.strip()]
        villages = list(Village.objects.filter(code__in=vcodes))
        inv.villages.set(villages)
        print(("created" if created else "updated"), "invitation", code, "villages", vcodes)

    # --- authority users ---
    for row in read_csv("users.csv"):
        username = (row.get("username") or "").strip()
        acode = (row.get("authority_code") or "").strip()
        if not username or not acode:
            continue
        auth = Authority.objects.get(code=acode)
        role = (row.get("role") or "OFC").strip() or "OFC"
        user = AuthorityUser.objects.filter(username=username).first()
        created = False
        if user is None:
            user = AuthorityUser(
                username=username,
                authority=auth,
                role=role,
            )
            created = True
        user.authority = auth
        user.role = role
        user.first_name = (row.get("first_name") or "").strip()
        user.last_name = (row.get("last_name") or "").strip()
        user.email = (row.get("email") or "").strip()
        user.is_staff = truthy(row.get("is_staff"), True)
        user.is_active = truthy(row.get("is_active"), True)
        user.is_superuser = truthy(row.get("is_superuser"), False)
        password = (row.get("password") or "").strip()
        if password:
            user.set_password(password)
        user.save()
        print(("created" if created else "updated"), "user", username, role, acode)

    # --- superusers (plain User) ---
    for row in read_csv("superusers.csv"):
        username = (row.get("username") or "").strip()
        if not username:
            continue
        user = User.objects.filter(username=username).first()
        created = False
        if user is None:
            user = User(username=username)
            created = True
        user.email = (row.get("email") or "").strip()
        user.is_staff = truthy(row.get("is_staff"), True)
        user.is_superuser = truthy(row.get("is_superuser"), True)
        user.is_active = True
        password = (row.get("password") or "").strip()
        if password:
            user.set_password(password)
        user.save()
        # also ensure demo-tenant AuthorityUser not required
        print(("created" if created else "updated"), "superuser", username)

    # --- report categories ---
    for row in read_csv("report_categories.csv"):
        name = (row.get("name") or "").strip()
        if not name:
            continue
        ordering = int((row.get("ordering") or "0").strip() or "0")
        cat = Category.objects.filter(name=name).first()
        created = False
        if cat is None:
            cat = Category(name=name)
            created = True
        cat.ordering = ordering
        cat.save()
        print(("created" if created else "updated"), "report_category", name, "ordering", ordering)

    # --- report types (form definitions under seeds/demo/) ---
    for row in read_csv("report_types.csv"):
        name = (row.get("name") or "").strip()
        cat_name = (row.get("category_name") or "").strip()
        def_rel = (row.get("definition_file") or "").strip()
        if not name or not cat_name:
            continue
        cat = Category.objects.filter(name=cat_name).first()
        if cat is None:
            cat = Category.objects.create(name=cat_name, ordering=0)
            print("created report_category (implicit)", cat_name)
        definition = {}
        if def_rel:
            def_path = seeds / def_rel
            if not def_path.exists():
                raise SystemExit(f"report type definition not found: {def_path}")
            with def_path.open(encoding="utf-8") as f:
                definition = json.load(f)
        published = truthy(row.get("published"), True)
        ordering = int((row.get("ordering") or "0").strip() or "0")
        is_followable = truthy(row.get("is_followable"), False)
        renderer = (row.get("renderer_data_template") or "").strip() or None
        rt = ReportType.objects.filter(name=name).first()
        created = False
        if rt is None:
            rt = ReportType(name=name, category=cat, definition=definition or {})
            created = True
        rt.category = cat
        if definition:
            rt.definition = definition
        rt.published = published
        rt.ordering = ordering
        rt.is_followable = is_followable
        if renderer is not None:
            rt.renderer_data_template = renderer
        rt.save()
        auth_codes = [
            c.strip()
            for c in (row.get("authority_codes") or "").split("|")
            if c.strip()
        ]
        if auth_codes:
            auths = list(Authority.objects.filter(code__in=auth_codes))
        else:
            # empty authority_codes => all authorities (demo convenience)
            auths = list(Authority.objects.all())
        rt.authorities.set(auths)
        print(
            ("created" if created else "updated"),
            "report_type",
            name,
            "category",
            cat_name,
            "published",
            published,
            "auths",
            len(auths),
            "sections",
            len((rt.definition or {}).get("sections", [])),
        )

    # --- census defaults (definitions/versions) ---
    for row in read_csv("census_defaults.csv"):
        if truthy(row.get("ensure_defaults"), True):
            seed_species = truthy(row.get("seed_species"), True)
            defs, vers = ensure_default_census_setup(seed_species=seed_species, reset_schema=False)
            print("census defaults", [(d.kind, d.id) for d in defs], "versions", len(vers))

    # --- census round definitions + materialize occurrences ---
    for row in read_csv("census_rounds.csv"):
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()
        kind = (row.get("kind") or "").strip().upper()
        if not code or not name or not kind:
            continue
        mode = (row.get("mode") or "PRODUCTION").strip().upper() or "PRODUCTION"
        enabled = truthy(row.get("enabled"), True)
        target_code = (row.get("target_authority_code") or "").strip()
        target = None
        if target_code:
            target = Authority.objects.filter(code=target_code).first()
            if target is None:
                raise SystemExit(f"census round target authority not found: {target_code}")

        definition = CensusRoundDefinition.objects.filter(code=code).first()
        created = False
        if definition is None:
            definition = CensusRoundDefinition(code=code)
            created = True
        definition.name = name
        definition.kind = kind
        definition.mode = mode
        definition.repeat = CensusRoundDefinition.Repeat.ANNUAL
        definition.census_period_start = (row.get("census_period_start") or "").strip()
        definition.census_period_end = (row.get("census_period_end") or "").strip()
        definition.start_date = (row.get("start_date") or "").strip()
        definition.soft_finish_date = (row.get("soft_finish_date") or "").strip()
        definition.hard_finish_date = (row.get("hard_finish_date") or "").strip()
        definition.target_authority = target
        definition.enabled = enabled

        errors = validate_round_definition(definition)
        if errors:
            raise SystemExit(f"census round {code} invalid: {errors}")

        definition.save()
        print(
            ("created" if created else "updated"),
            "census_round",
            code,
            kind,
            mode,
            "enabled",
            enabled,
            "target",
            target_code or "*",
        )

        from_year_raw = (row.get("materialize_from_year") or "").strip()
        years_raw = (row.get("materialize_years") or "1").strip() or "1"
        if enabled and from_year_raw:
            from_year = int(from_year_raw)
            years = int(years_raw)
            occurrences = materialize_occurrences(definition, from_year, years)
            print(
                "  materialized",
                [(o.year, o.occurrence_key, str(o.start_date), str(o.hard_finish_date)) for o in occurrences],
            )

print("done")
PY

echo "Demo seeds applied."
