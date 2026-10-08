from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class EmptyConfigCliTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qa-config-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.calls = self.directory / "provider_calls"
        self.config = self.directory / "gcloud_config.json"
        self.environment = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "QA_TEST_CONFIG": str(self.config),
            "QA_TEST_CALLS": str(self.calls),
        }
        gcloud = self.bin / "gcloud"
        gcloud.write_text(
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "with open(os.environ['QA_TEST_CALLS'], 'a') as calls:\n"
            "    calls.write(sys.argv[1] + '\\n')\n"
            "if sys.argv[1:] == ['config', 'list', '--all', '--format=json']:\n"
            "    print(pathlib.Path(os.environ['QA_TEST_CONFIG']).read_text())\n"
            "    raise SystemExit(0)\n"
            "assert sys.argv[1:] == ['auth', 'print-access-token']\n"
            "print('SECRET_SENTINEL', file=sys.stderr)\n"
            "raise SystemExit(9)\n",
            encoding="utf-8",
        )
        gcloud.chmod(0o700)

    def run_firestore(self, config, project="susugigi-qa"):
        self.config.write_text(json.dumps(config), encoding="utf-8")
        return subprocess.run(
            [sys.executable, "-I", str(ROOT / "programs/qa-firestore-read.py"),
             "--project", project, "--profile", "r01-user-anonymous"],
            input="qa-config-test-user\n",
            text=True,
            capture_output=True,
            env=self.environment,
            cwd=self.directory,
            timeout=20,
        )

    def test_unset_gcloud_sections_reach_credential_provider(self):
        result = self.run_firestore({
            "api_endpoint_overrides": {"firestore": None, "iam": None},
            "proxy": {"address": None, "port": None, "type": None},
        })
        self.assertEqual(
            (result.returncode, result.stdout, result.stderr, self.calls.read_text()),
            (1, "", "QA_FIRESTORE_PROBE_FAILED\n", "config\nauth\n"),
        )

    def run_auth(self, config, project="susugigi-qa"):
        fake_home = self.directory / "test_home"
        config_path = fake_home / ".config/configstore/firebase-tools.json"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(config), encoding="utf-8")
        firebase = self.bin / "firebase"
        firebase.write_text(
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "assert sys.argv[1:5] == ['--project', 'susugigi-qa', '--non-interactive', 'auth:export']\n"
            "assert sys.argv[6:] == ['--format', 'json']\n"
            "with open(os.environ['QA_TEST_CALLS'], 'a') as calls:\n"
            "    calls.write('auth:export\\n')\n"
            "pathlib.Path(sys.argv[5]).write_text('{\"users\": []}')\n",
            encoding="utf-8",
        )
        firebase.chmod(0o700)
        launcher = (
            "import pathlib, runpy, sys\n"
            "from unittest.mock import patch\n"
            "target, fake_home = sys.argv[1:3]\n"
            "sys.argv = [target, *sys.argv[3:]]\n"
            "with patch.object(pathlib.Path, 'home', return_value=pathlib.Path(fake_home)):\n"
            "    runpy.run_path(target, run_name='__main__')\n"
        )
        return subprocess.run(
            [sys.executable, "-I", "-c", launcher,
             str(ROOT / "programs/qa-firebase-auth-absence.py"), str(fake_home),
             "--project", project],
            input="a" * 64 + "\n",
            text=True,
            capture_output=True,
            env=self.environment,
            cwd=self.directory,
            timeout=20,
        )

    def test_unset_firebase_sections_allow_qa_auth_export(self):
        result = self.run_auth({
            "proxy": {"address": None},
            "api_endpoint_overrides": {"identitytoolkit": None},
        })
        calls = self.calls.read_text() if self.calls.exists() else ""
        self.assertEqual(
            (result.returncode, result.stdout, result.stderr, calls),
            (0, "QA_AUTH_IDENTITY_ABSENT\n", "", "auth:export\n"),
        )

    def test_configured_overrides_block_before_credentials(self):
        configurations = (
            {"proxy": {"address": "attacker.invalid"}},
            {"api_endpoint_overrides": {"firestore": "https://attacker.invalid"}},
            {"proxy": [None, {}, {"address": [{"host": "attacker.invalid"}]}]},
            {"safe": {"options": [{"CUSTOM_CA_CERTS_FILE": "/tmp/untrusted-ca"}]}},
            {"safe": {"options": [{"ToKeN_HoSt": "https://attacker.invalid/token"}]}},
            {"proxy": {"port": 8080}},
            {"proxy": {"enabled": True}},
            {"proxy": {"port": 0}},
            {"proxy": {"enabled": False}},
            {"proxy": {"values": [False]}},
            {"proxy": {"address": " "}},
            {"endpoint": [["", None], {"target": "https://attacker.invalid"}]},
        )
        for driver in ("firestore", "auth"):
            for index, config in enumerate(configurations):
                with self.subTest(driver=driver, configuration=index):
                    self.calls.unlink(missing_ok=True)
                    result = self.run_firestore(config) if driver == "firestore" else self.run_auth(config)
                    calls = self.calls.read_text() if self.calls.exists() else ""
                    self.assertEqual(
                        (result.returncode, result.stdout, result.stderr, calls),
                        (1, "", "QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED\n",
                         "config\n" if driver == "firestore" else ""),
                    )

    def test_nested_empty_containers_do_not_enable_overrides(self):
        config = {
            "proxy": [None, "", {}, [], {"address": [None, {"value": ""}]}],
            "api_endpoint_overrides": {"firestore": None},
        }
        for driver in ("firestore", "auth"):
            with self.subTest(driver=driver):
                self.calls.unlink(missing_ok=True)
                result = self.run_firestore(config) if driver == "firestore" else self.run_auth(config)
                expected = (
                    (1, "", "QA_FIRESTORE_PROBE_FAILED\n", "config\nauth\n")
                    if driver == "firestore"
                    else (0, "QA_AUTH_IDENTITY_ABSENT\n", "", "auth:export\n")
                )
                calls = self.calls.read_text() if self.calls.exists() else ""
                self.assertEqual((result.returncode, result.stdout, result.stderr, calls), expected)

    def test_nonobject_config_still_fails_closed(self):
        for driver in ("firestore", "auth"):
            for config in (None, [], "not-a-config-object"):
                with self.subTest(driver=driver, configuration=config):
                    self.calls.unlink(missing_ok=True)
                    result = self.run_firestore(config) if driver == "firestore" else self.run_auth(config)
                    calls = self.calls.read_text() if self.calls.exists() else ""
                    expected_error = (
                        "QA_FIRESTORE_AUTH_PROVIDER_UNAVAILABLE\n"
                        if driver == "firestore"
                        else "QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED\n"
                    )
                    self.assertEqual(
                        (result.returncode, result.stdout, result.stderr, calls),
                        (1, "", expected_error, "config\n" if driver == "firestore" else ""),
                    )

    def test_production_project_stays_blocked_before_provider_execution(self):
        config = {"proxy": {"address": None}}
        for driver in ("firestore", "auth"):
            with self.subTest(driver=driver):
                self.calls.unlink(missing_ok=True)
                runner = self.run_firestore if driver == "firestore" else self.run_auth
                result = runner(config, project="susugigi-c4fb1")
                calls = self.calls.read_text() if self.calls.exists() else ""
                expected_error = (
                    "QA_FIRESTORE_PROBE_FAILED\n"
                    if driver == "firestore"
                    else "QA_AUTH_ABSENCE_PROBE_FAILED\n"
                )
                self.assertEqual(
                    (result.returncode, result.stdout, result.stderr, calls),
                    (1, "", expected_error, ""),
                )


if __name__ == "__main__":
    unittest.main()
