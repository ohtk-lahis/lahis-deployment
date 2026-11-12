import csv
import json
import unittest
from pathlib import Path

from django.template import Context, Engine


class AnimalSummaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / "seeds/demo/report_types.csv"
        with path.open(encoding="utf-8-sig", newline="") as source:
            row = next(csv.DictReader(source))
        cls.template = Engine().from_string(row["renderer_data_template"])

    def render_summary(self, **data):
        return self.template.render(Context({"data": {"animal_species": "Cattle", "num_sick": 1, "num_dead": 0, **data}, "incident_date": "2026-11-12"}, use_l10n=False))

    def test_unknown_total_is_not_displayed_as_zero(self):
        for data in ({}, {"num_total_animal": None}, {"num_total_animal": ""}):
            with self.subTest(data=data):
                text = self.render_summary(**data)
                self.assertIn("Cattle: 1 sick, 0 dead", text)
                self.assertNotIn("(of", text)

    def test_invalid_zero_total_is_not_presented_as_known(self):
        self.assertNotIn("(of", self.render_summary(num_total_animal=0))

    def test_positive_total_remains_visible(self):
        self.assertIn("(of 20)", self.render_summary(num_total_animal=20))


class LaoAnimalSummaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / "seeds/tot/report-setup.json"
        report = json.loads(path.read_text(encoding="utf-8"))["reports"][0]
        cls.templates = {
            key: Engine().from_string(report[key])
            for key in ("renderer_data_template", "renderer_followup_data_template")
        }

    def render_summaries(self, **data):
        context = Context({"data": {"num_sick": 1, **data},
                           "incident_data": {"animal_species": "Cattle"}}, use_l10n=False)
        return {key: template.render(context) for key, template in self.templates.items()}

    def test_unknown_or_invalid_total_is_not_displayed_as_zero(self):
        for data in ({}, {"num_total_animal": None}, {"num_total_animal": ""},
                     {"num_total_animal": 0}):
            for key, text in self.render_summaries(**data).items():
                with self.subTest(data=data, template=key):
                    self.assertIn("ປ່ວຍ 1 ໂຕ", text)
                    self.assertNotIn("ທັງໝົດ", text)

    def test_positive_total_remains_visible(self):
        for key, text in self.render_summaries(num_total_animal=20).items():
            with self.subTest(template=key):
                self.assertIn("ທັງໝົດ 20 ໂຕ", text)


if __name__ == "__main__":
    unittest.main()
