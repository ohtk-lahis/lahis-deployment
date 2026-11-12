import csv
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


if __name__ == "__main__":
    unittest.main()
