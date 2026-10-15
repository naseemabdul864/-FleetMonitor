import os
import unittest
from pathlib import Path

import pandas as pd

from app.data_access import _demo_maintenance, _demo_schedules, _demo_vehicles


ROOT = Path(__file__).resolve().parents[1]


class ProjectSmokeTests(unittest.TestCase):
    def test_required_files_exist(self):
        required = [
            "README.md",
            "docker-compose.yml",
            ".env.example",
            "requirements.txt",
            "db/postgres/01_schema.sql",
            "db/postgres/02_seed.sql",
            "db/postgres/03_optimization.sql",
            "db/postgres/04_concurrency.sql",
            "db/postgres/05_distribution.sql",
            "db/mongo/01_setup.js",
            "db/mongo/02_sample_documents.js",
            "app/dashboard.py",
            "app/data_access.py",
            "scripts/setup_local.ps1",
            "scripts/run_dashboard.ps1",
        ]
        for relative_path in required:
            self.assertTrue((ROOT / relative_path).exists(), relative_path)

    def test_demo_data_has_dashboard_columns(self):
        vehicles = _demo_vehicles()
        schedules = _demo_schedules()
        maintenance = _demo_maintenance()
        self.assertGreaterEqual(len(vehicles), 5)
        self.assertTrue({"vehicle_id", "registration_no", "status"}.issubset(vehicles.columns))
        self.assertTrue({"schedule_id", "scheduled_start", "status"}.issubset(schedules.columns))
        self.assertTrue({"work_order_id", "due_at", "estimated_cost"}.issubset(maintenance.columns))
        self.assertFalse(schedules.empty)
        self.assertFalse(maintenance.empty)
        self.assertTrue(pd.api.types.is_numeric_dtype(maintenance["estimated_cost"]))

    def test_sql_contains_safety_features(self):
        schema = (ROOT / "db/postgres/01_schema.sql").read_text(encoding="utf-8")
        seed = (ROOT / "db/postgres/02_seed.sql").read_text(encoding="utf-8")
        optimization = (ROOT / "db/postgres/03_optimization.sql").read_text(encoding="utf-8")
        self.assertIn("REFERENCES vehicle(vehicle_id)", schema)
        self.assertIn("PostgreSQL is the relational source of truth", schema)
        self.assertIn("Seed the PostgreSQL relational source of truth", seed)
        self.assertIn("CHECK", schema)
        self.assertIn("EXPLAIN (ANALYZE, BUFFERS", optimization)
        self.assertIn("CREATE INDEX", optimization)

    def test_postgresql_is_explicitly_configured(self):
        compose = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        access = (ROOT / "app/data_access.py").read_text(encoding="utf-8")
        self.assertIn("image: postgres:16", compose)
        self.assertIn("POSTGRES_SOURCE_OF_TRUTH", compose)
        self.assertIn("PostgreSQL is the relational source of truth", readme)
        self.assertIn("PostgreSQL is authoritative", access)
        self.assertIn("FROM vehicle", access)
        self.assertIn("v_vehicle_schedule", access)
        dashboard = (ROOT / "app/dashboard.py").read_text(encoding="utf-8")
        self.assertIn("POSTGRES_SOURCE_OF_TRUTH", dashboard)

    def test_beginner_setup_is_documented(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        mongo_setup = (ROOT / "db/mongo/01_setup.js").read_text(encoding="utf-8")
        setup_script = (ROOT / "scripts/setup_local.ps1").read_text(encoding="utf-8")
        self.assertIn(".\\scripts\\setup_local.ps1", readme)
        self.assertIn("psql", readme)
        self.assertIn("mongosh", readme)
        self.assertIn("bsonType: [\"int\", \"long\"]", mongo_setup)
        self.assertIn("01_schema.sql", setup_script)
        self.assertIn("01_setup.js", setup_script)


if __name__ == "__main__":
    unittest.main()
