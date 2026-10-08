#!/usr/bin/env python3

import csv
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class R13PrepareOrderTests(unittest.TestCase):
    def test_identity_cleanup_and_prepare_precede_app_data_access(self):
        with (ROOT / "no3_run_scripts/no15_r13_backfill_verification.csv").open() as handle:
            rows = list(csv.DictReader(handle))

        def position(method, phrase):
            matches = [index for index, row in enumerate(rows)
                       if row["手段"] == method and phrase in row["動作"]]
            self.assertEqual(len(matches), 1, (method, phrase))
            return matches[0]

        auth = position("firebase-auth-control", "QA_SESSION_UID")
        cleanup = position("qa-cleanup", "post-delete absent probes")
        prepare = position("qa-command", "prepare r09_stale_schedule")
        identity = position("sqlite-local", "QA_SESSION_UID")
        inspect = position("qa-probe", "inspect accounting.schedule-backfill")
        self.assertLess(auth, cleanup)
        self.assertLess(cleanup, prepare)
        self.assertLess(prepare, identity)
        self.assertLess(identity, inspect)
        self.assertFalse(any(row["手段"] == "sqlite-local" for row in rows[:prepare]))
        self.assertFalse(any("open-app-" in row["動作"] for row in rows[:prepare]))
        self.assertEqual(rows[5]["序"], "6")
        self.assertIn("r13_schedule_backfill 聚合 profile", rows[5]["動作"])
        self.assertEqual(rows[7]["序"], "8")
        self.assertIn("QA SCHED backfill log", rows[7]["動作"])


if __name__ == "__main__":
    unittest.main()
