#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(os.environ["QA_QUALITY_TEST_ROOT"]) / "no3_run_scripts/control_adapter/programs/qa-session-runtime.sh"


os.environ.setdefault("QA_CONTROL_TEST_ROOT", str(Path(__file__).resolve().parents[2]))


class LifecycleTests(unittest.TestCase):
    def run_loop(self, input_text, health="return 0", cleanup="return 0"):
        with tempfile.TemporaryDirectory() as temporary:
            events = Path(temporary) / "events"
            body = f'''
source "$1"
SESSION_CONTROL_PLANE_ROOT="$QA_CONTROL_TEST_ROOT"
SESSION_QUALITY_ROOT="$QA_QUALITY_TEST_ROOT"
require_runtime_marker_session_clean() {{ {health}; }}
require_session_runtime_snapshots_current() {{ return 0; }}
run_session_snapshot_command() {{ "$@"; }}
run_and_validate_qa_open_app_operation() {{ printf 'open\\n' >> "$2"; }}
cleanup_sim_review() {{ printf 'cleanup\\n' >> "$2"; {cleanup}; }}
QA_SESSION_TOKEN=secret-not-for-output
QA_SESSION_IDLE_TIMEOUT=1
qa_session_command_loop
'''
            # Functions retain positional parameters only when called with them explicitly.
            body = body.replace('"$2"', '"$QA_TEST_EVENTS"')
            result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", body,
                                     "qa-test", str(SCRIPT), str(events)], input=input_text,
                                    capture_output=True, text=True, timeout=5,
                                    env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                                         "QA_CONTROL_TEST_ROOT": str(Path(__file__).resolve().parents[2]),
                                         "QA_QUALITY_TEST_ROOT": os.environ["QA_QUALITY_TEST_ROOT"],
                                         "QA_TEST_EVENTS": str(events)})
            return result, events.read_text() if events.exists() else ""

    def test_finish_cleans_once(self):
        result, events = self.run_loop("status\nfinish\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events, "cleanup\n")
        self.assertNotIn("secret-not-for-output", result.stdout + result.stderr)

    def test_eof_and_unknown_command_fail_and_clean(self):
        for command in ("", "touch /tmp/should-never-execute\n", "abort\n"):
            with self.subTest(command=command):
                result, events = self.run_loop(command)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(events, "cleanup\n")

    def test_taint_during_wait_prevents_dispatch(self):
        result, events = self.run_loop("open-app\nfinish\n", health="return 1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, "cleanup\n")

    def test_cleanup_failure_never_reports_success(self):
        result, events = self.run_loop("finish\n", cleanup="return 1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, "cleanup\n")

    def test_open_app_is_dispatched_without_eval(self):
        result, events = self.run_loop("open-app\nfinish\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events, "open\ncleanup\n")

    def test_signal_and_idle_timeout_clean_up(self):
        for send_signal in (False, True):
            with self.subTest(signal=send_signal), tempfile.TemporaryDirectory() as temporary:
                events = Path(temporary) / "events"
                body = '''source "$1"
SESSION_CONTROL_PLANE_ROOT="$QA_CONTROL_TEST_ROOT"
SESSION_QUALITY_ROOT="$QA_QUALITY_TEST_ROOT"
require_runtime_marker_session_clean() { return 0; }
require_session_runtime_snapshots_current() { return 0; }
run_session_snapshot_command() { "$@"; }
cleanup_sim_review() { printf cleanup >> "$QA_TEST_EVENTS"; }
QA_SESSION_IDLE_TIMEOUT=1
qa_session_command_loop
'''
                process = subprocess.Popen(["/bin/bash", "--noprofile", "--norc", "-c", body,
                                            "qa-test", str(SCRIPT)], stdin=subprocess.PIPE,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                           env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                                                "QA_CONTROL_TEST_ROOT": str(Path(__file__).resolve().parents[2]),
                                         "QA_QUALITY_TEST_ROOT": os.environ["QA_QUALITY_TEST_ROOT"],
                                         "QA_TEST_EVENTS": str(events)})
                if send_signal:
                    time.sleep(.3)
                    process.send_signal(signal.SIGTERM)
                process.wait(timeout=5)
                process.communicate()
                self.assertNotEqual(process.returncode, 0)
                self.assertEqual(events.read_text(), "cleanup")

    def test_bash_32_wait_survives_one_second_without_eof(self):
        body = '''source "$1"
SESSION_CONTROL_PLANE_ROOT="$QA_CONTROL_TEST_ROOT"
SESSION_QUALITY_ROOT="$QA_QUALITY_TEST_ROOT"
require_runtime_marker_session_clean() { return 0; }
require_session_runtime_snapshots_current() { return 0; }
run_session_snapshot_command() { "$@"; }
cleanup_sim_review() { return 0; }
QA_SESSION_IDLE_TIMEOUT=4
qa_session_command_loop
'''
        process = subprocess.Popen(["/bin/bash", "--noprofile", "--norc", "-c", body,
                                    "qa-test", str(SCRIPT)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            time.sleep(1.5)
            self.assertIsNone(process.poll())
            output, error = process.communicate(b"finish\n", timeout=5)
            self.assertEqual(process.returncode, 0, error)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


if __name__ == "__main__":
    unittest.main()
