#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "programs/qa-runtime-selection.py"
spec = importlib.util.spec_from_file_location("selection", SCRIPT)
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.payload = {"sceneIds": ["R01", "R03"], "caseIds": ["AU-01", "CS-02"],
                        "expectedEvidence": {"R01": [{"測項": "AU-01", "已驗": ""}],
                                             "R03": [{"測項": "CS-02", "已驗": ""}]},
                        "qaLaunchArguments": {"AU-01": [["--qa-open-app", "true"]],
                                              "CS-02": [["--qa-prepare", "r02_end"],
                                                        ["--qa-inspect", "accounting.fixture-summary"]]}}

    def test_selected_case_keeps_exact_arguments(self):
        self.assertEqual(selection.resolve(self.payload, "R03", "CS-02"),
                         ("r02_end", "accounting.fixture-summary"))

    def test_wrong_scene_or_unselected_case_is_rejected(self):
        for scene, case in (("R01", "CS-02"), ("R03", "CS-99"), ("R12", "AU-01")):
            with self.subTest(scene=scene, case=case), self.assertRaises(ValueError):
                selection.resolve(self.payload, scene, case)

    def test_unknown_duplicate_mixed_or_shell_arguments_are_rejected(self):
        for arguments in ([["--qa-prepare", "r99_unknown"]], [["--qa-open-app", "true"]] * 2,
                          [["--qa-open-app", "true"], ["--qa-prepare", "r02_end"]],
                          [["--qa-prepare", "$(touch sentinel)"]], []):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                payload = copy.deepcopy(self.payload)
                payload["qaLaunchArguments"]["CS-02"] = arguments
                selection.resolve(payload, "R03", "CS-02")


if __name__ == "__main__":
    unittest.main()
