#!/usr/bin/env python3
"""Load from Django shell; main([...]) previews unless --apply is explicit."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path

CONFIG_FIELDS = (
    "name", "definition", "followup_definition", "metric_accumulation",
    "close_definition", "renderer_data_template", "renderer_followup_data_template",
)
TEXT_FIELDS = ("name", "renderer_data_template", "renderer_followup_data_template")
CONFIG_KEY = "cases.lahis_summarized_report_type_name"


def read_seed(seed_dir):
    """Read the existing report-setup format, ignoring all unapproved sections."""
    seed = Path(seed_dir).resolve(strict=True)
    setup = json.loads((seed / "report-setup.json").read_text(encoding="utf-8"))
    reports = setup["reports"]
    if len(reports) != 1:
        raise ValueError("Expected exactly one report in report-setup.json")
    result = {key: reports[0][key] for key in CONFIG_FIELDS}
    selectors = [c for c in setup.get("configurations", []) if c.get("key") == CONFIG_KEY]
    if selectors != [{"key": CONFIG_KEY, "value": result["name"]}]:
        raise ValueError("Expected exactly one matching summarized report type selector")
    return result


def serialized(value):
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, default=str)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-dir", required=True)
    parser.add_argument("--tenant", required=True, help="Explicit tenant schema")
    parser.add_argument("--report-type-id", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-preview", help="SHA256 printed by the reviewed preview")
    args = parser.parse_args(argv)
    if args.apply and not args.expected_preview:
        parser.error("--apply requires --expected-preview from a reviewed preview")
    proposed = read_seed(args.seed_dir)

    from django.db import connection, transaction
    from django.template import Context, Template
    from django_tenants.utils import get_tenant_model, schema_context
    from accounts.models import Configuration
    from reports.models import ReportType

    if args.tenant == "public":
        raise ValueError("A report tenant is required; public is not allowed")
    get_tenant_model().objects.get(schema_name=args.tenant)
    # Compile before writing. Runtime/template-language acceptance is separate.
    for key in TEXT_FIELDS[1:]:
        Template(proposed[key]).render(Context({}))
    with schema_context(args.tenant), transaction.atomic():
        rt = ReportType.objects.select_for_update().get(pk=args.report_type_id)
        config = Configuration.objects.select_for_update().filter(key=CONFIG_KEY).first()
        current = {key: getattr(rt, key) for key in proposed}
        # Include identity, flags, workflow, timestamps and authority links in the guard.
        snapshot = {f.attname: getattr(rt, f.attname) for f in rt._meta.concrete_fields}
        snapshot["authorities"] = sorted(str(x) for x in rt.authorities.values_list("pk", flat=True))
        config_before = None if config is None else config.value
        guard = {
            "database": connection.settings_dict["NAME"], "tenant": args.tenant,
            "report_type": snapshot, "configuration_before": config_before,
            "proposed": proposed, "configuration_after": proposed["name"],
        }
        digest = hashlib.sha256(serialized(guard).encode()).hexdigest()
        before = {"report_type": current, "configuration": {CONFIG_KEY: config_before}}
        after = {"report_type": proposed, "configuration": {CONFIG_KEY: proposed["name"]}}
        print("database:", guard["database"], "tenant:", args.tenant, "report_type:", rt.pk)
        print("preview_sha256:", digest)
        print("".join(difflib.unified_diff(
            (serialized(before) + "\n").splitlines(True),
            (serialized(after) + "\n").splitlines(True),
            fromfile="current", tofile="seed",
        )))
        changed = [key for key in proposed if current[key] != proposed[key]]
        config_changed = config_before != proposed["name"]
        if not args.apply:
            print("PREVIEW ONLY; changed report fields:", ", ".join(changed) or "none")
            return
        if digest != args.expected_preview:
            raise ValueError("Preview changed; inspect a fresh preview before applying")
        if changed:
            for key in changed:
                setattr(rt, key, proposed[key])
            rt.save(update_fields=changed + ["updated_at"])
        if config_changed:
            Configuration.objects.update_or_create(key=CONFIG_KEY, defaults={"value": proposed["name"]})
        print("APPLIED" if changed or config_changed else "NO CHANGES", "(report identity and relations preserved)")


if __name__ == "__main__":
    main()
