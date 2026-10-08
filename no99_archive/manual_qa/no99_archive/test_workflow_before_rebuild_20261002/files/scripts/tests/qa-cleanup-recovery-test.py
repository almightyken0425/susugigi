#!/usr/bin/env python3
"""Offline contract tests. No simulator, credentials or Firebase access."""
import os
import hashlib
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

CONTROL = Path(__file__).resolve().parents[2]
TEXT = subprocess.check_output(["python3", "-B", str(CONTROL / "scripts/render_qa_contract.py"), "--quality-root", os.environ["QA_QUALITY_TEST_ROOT"]], text=True)
UID = "fake-cleanup-test-uid"


def function(name):
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", TEXT, re.M | re.S)
    if not match:
        raise AssertionError("Missing function: " + name)
    return match.group()


FUNCTIONS = "\n".join(function(name) for name in (
    "run_bound_qa_fixture_cleanup", "verify_qa_fixture_cleanup_absence",
    "cleanup_qa_fixtures_if_required",
))


class RecoveryTests(unittest.TestCase):
    def test_session_registration_cleanup_on_normal_and_error_exit(self):
        quality = Path(os.environ["QA_QUALITY_TEST_ROOT"])
        restore = quality / "no3_run_scripts/control_adapter/ios_runtime/restore_1.sh"
        for normal in (False, True):
            with self.subTest(normal=normal), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                repo = root / "repo"
                repo.mkdir()
                subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
                subprocess.run(["git", "-C", str(repo), "-c", "user.name=QA",
                                "-c", "user.email=qa@example.invalid", "-c", "commit.gpgsign=false",
                                "commit", "--allow-empty", "-qm", "fixture"], check=True)
                stream = root / "stream"
                stream.mkdir(mode=0o700)
                (stream / "launch.json").write_text('{}\n')
                os.mkfifo(stream / "stdout")
                script = function("cleanup_sim_review") + r'''
SIM_REVIEW_CLEANUP_RUNNING=0
SESSION_FAILED=0
MAIN_RESTORE_REQUIRED=0
MAIN_QA_FIREBASE_CREATED=0
MAIN_START_HEAD="$(git -C "$MAIN_REPO" rev-parse HEAD)"
METRO_PID= METRO_FILTER_PID= QA_APP_CONSOLE_PID= READY_MARKER_LOG=
SYNTHETIC_INDEX= SYNTHETIC_TMP= QA_BUNDLE_ID= TARGET_KIND=release-commit
cleanup_qa_fixtures_if_required() { :; }
dispose_qa_identity_if_required() { :; }
remove_main_qa_firebase_config() { :; }
cleanup_session_runtime_snapshots() { :; }
stop_qa_app_console_capture_with_deadline() { :; }
xcrun() { :; }
npx() { printf unexpected-restart >> "$TEST_ROOT/restarted"; }
'''
                if normal:
                    script += "source " + shlex.quote(str(restore)) + "\nwait\n"
                else:
                    script += "trap cleanup_sim_review EXIT\nexit 7\n"
                result = subprocess.run(["/bin/bash", "-c", script], capture_output=True,
                    text=True, timeout=5, env={"PATH": "/usr/bin:/bin", "TEST_ROOT": directory,
                    "MAIN_REPO": str(repo), "METRO_STREAM_TMP": str(stream),
                    "METRO_STREAM_FIFO": str(stream / "stdout")})
                self.assertEqual(result.returncode, 0 if normal else 7, result.stderr)
                self.assertFalse(stream.exists())
                self.assertFalse((root / "restarted").exists())

    def run_cleanup(self, statuses="0", probe="absent", binding=True,
                    snapshot_failure=0, required=True, repeat=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "no2_qa_tools/cleanup_qa_fixtures.sh"
            helper.parent.mkdir()
            helper.write_text("# stub; never executed\n")
            (root / "statuses").write_text(statuses.replace(",", "\n") + "\n")
            script = FUNCTIONS + r'''
require_session_runtime_snapshots_current() {
  printf 'check\n' >> "$TEST_ROOT/checks"
  local count="$(/usr/bin/wc -l < "$TEST_ROOT/checks" | /usr/bin/tr -d ' ')"
  [ "$count" != "$TEST_SNAPSHOT_FAILURE" ]
}
run_session_snapshot_command() {
  local input status
  IFS= read -r input
  [ "$input" = "$QA_SESSION_UID" ] || return 99
  printf 'delete\n' >> "$TEST_ROOT/events"
  local count="$(/usr/bin/wc -l < "$TEST_ROOT/events" | /usr/bin/tr -d ' ')"
  status="$(/usr/bin/sed -n "${count}p" "$TEST_ROOT/statuses")"
  printf '%s\n' "$QA_SESSION_UID"
  printf 'raw-secret-response\n' >&2
  return "${status:-99}"
}
qa_firestore_read_driver() {
  printf 'probe\n' >> "$TEST_ROOT/probes"
  case "$TEST_PROBE" in
    absent) printf '%s\n' QA_FIRESTORE_FIXTURE_SUBTREE_ABSENT ;;
    wrong) printf '%s\n' raw-secret-response ;;
    *) printf '%s\n' raw-secret-response >&2; return 1 ;;
  esac
}
SESSION_QUALITY_ROOT="$TEST_ROOT"
QA_FIREBASE_PROJECT_ID=susugigi-qa
FIXTURE_CLEANUP_CONFIRMED=0
FIXTURE_CLEANUP_ATTEMPTED=0
FIXTURE_CLEANUP_FAILED=0
cleanup_qa_fixtures_if_required
result=$?
if [ "$TEST_REPEAT" = 1 ]; then cleanup_qa_fixtures_if_required; fi
printf 'confirmed=%s failed=%s\n' "$FIXTURE_CLEANUP_CONFIRMED" "$FIXTURE_CLEANUP_FAILED"
exit "$result"
'''
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-c", script],
                capture_output=True, text=True, timeout=15,
                env={"PATH": "/usr/bin:/bin", "TEST_ROOT": directory,
                     "QA_SESSION_UID": UID,
                     "READY_IDENTITY_HASH": hashlib.sha256(UID.encode()).hexdigest() if binding else "wrong",
                     "TEST_PROBE": probe, "TEST_SNAPSHOT_FAILURE": str(snapshot_failure),
                     "FIXTURE_CLEANUP_REQUIRED": "1" if required else "0",
                     "TEST_REPEAT": "1" if repeat else "0"},
            )
            events = (root / "events").read_text().splitlines() if (root / "events").exists() else []
            probes = (root / "probes").read_text().splitlines() if (root / "probes").exists() else []
            self.assertNotIn(UID, result.stdout + result.stderr)
            self.assertNotIn("raw-secret-response", result.stdout + result.stderr)
            return result, events, probes

    def test_success_requires_absence_and_is_idempotent(self):
        result, events, probes = self.run_cleanup(repeat=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events, ["delete"])
        self.assertEqual(probes, ["probe"])
        self.assertIn("QA_FIXTURE_CLEANUP_VERIFIED", result.stdout)
        self.assertIn("confirmed=1 failed=0", result.stdout)

    def test_bounded_retry_keeps_same_identity(self):
        result, events, probes = self.run_cleanup("75,76,0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(events), 3)
        self.assertEqual(len(probes), 1)
        self.assertEqual(result.stderr.count("QA_FIXTURE_CLEANUP_RETRY\n"), 2)

    def test_exhausted_retries_block_recovery_and_cannot_repeat(self):
        result, events, probes = self.run_cleanup("75,76,75,0", repeat=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(events), 3)
        self.assertEqual(probes, [])
        self.assertIn("QA_FIXTURE_RECOVERY_BLOCKED", result.stderr)
        self.assertNotIn("QA_FIXTURE_CLEANUP_VERIFIED", result.stdout)

    def test_permanent_and_unknown_errors_do_not_retry(self):
        for status in (1, 2, 20, 21, 22, 24, 25, 26, 27, 99):
            with self.subTest(status=status):
                result, events, probes = self.run_cleanup(str(status) + ",0")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(events), 1)
                self.assertEqual(probes, [])
                self.assertNotIn("QA_FIXTURE_CLEANUP_RETRY", result.stderr)

    def test_missing_binding_or_snapshot_prevents_delete(self):
        for arguments in ({"binding": False}, {"snapshot_failure": 1}):
            result, events, probes = self.run_cleanup(**arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(events, [])
            self.assertEqual(probes, [])

    def test_post_snapshot_failure_overrides_retry(self):
        result, events, probes = self.run_cleanup("75,0", snapshot_failure=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(events), 1)
        self.assertEqual(probes, [])
        self.assertIn("phase=snapshot", result.stderr)
        self.assertNotIn("QA_FIXTURE_CLEANUP_RETRY", result.stderr)

    def test_snapshot_drift_between_attempts_prevents_next_delete(self):
        result, events, probes = self.run_cleanup("75,0", snapshot_failure=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(events), 1)
        self.assertEqual(probes, [])

    def test_absence_failure_never_repeats_deletion_or_claims_success(self):
        for probe in ("wrong", "failed"):
            with self.subTest(probe=probe):
                result, events, probes = self.run_cleanup(probe=probe)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(events), 1)
                self.assertEqual(len(probes), 1)
                self.assertIn("phase=absence", result.stderr)
                self.assertNotIn("QA_FIXTURE_CLEANUP_VERIFIED", result.stdout)

    def test_not_required_is_not_reported_as_verified(self):
        result, events, probes = self.run_cleanup(required=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(events, [])
        self.assertEqual(probes, [])
        self.assertNotIn("QA_FIXTURE_CLEANUP_VERIFIED", result.stdout)

    def test_fixture_failure_still_disposes_and_restores(self):
        script = function("cleanup_sim_review") + r'''
SIM_REVIEW_CLEANUP_RUNNING=0
SESSION_FAILED=0
MAIN_RESTORE_REQUIRED=1
MAIN_REPO=/unused
MAIN_START_HEAD=unused
MAIN_QA_FIREBASE_CREATED=0
METRO_PID= SYNTHETIC_INDEX= SYNTHETIC_TMP=
cleanup_qa_fixtures_if_required() { printf 'fixture\n'; return 1; }
dispose_qa_identity_if_required() { printf 'dispose\n'; return 1; }
remove_main_qa_firebase_config() { printf 'restore\n'; MAIN_RESTORE_REQUIRED=0; }
cleanup_session_runtime_snapshots() { printf 'private-cleanup\n'; }
cleanup_sim_review
'''
        result = subprocess.run(["/bin/bash", "-c", script], capture_output=True,
                                text=True, timeout=5, env={"PATH": "/usr/bin:/bin"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "fixture\ndispose\nrestore\nprivate-cleanup\n")

    def test_disposal_verified_marker_requires_validator_success(self):
        for verdict in (0, 1):
            script = function("dispose_qa_identity_if_required") + f'''
IDENTITY_TEARDOWN_POSSIBLE=1
IDENTITY_TEARDOWN_RUNNING=0
IDENTITY_TEARDOWN_ATTEMPTED=0
IDENTITY_TEARDOWN_FAILED=0
run_and_validate_qa_identity_disposal() {{ return {verdict}; }}
report_identity_teardown_failure() {{ :; }}
dispose_qa_identity_if_required
'''
            result = subprocess.run(["/bin/bash", "-c", script], capture_output=True,
                                    text=True, timeout=5, env={"PATH": "/usr/bin:/bin"})
            self.assertEqual(result.returncode, verdict)
            self.assertEqual("QA_IDENTITY_DISPOSAL_VERIFIED" in result.stdout, verdict == 0)


if __name__ == "__main__":
    unittest.main()
