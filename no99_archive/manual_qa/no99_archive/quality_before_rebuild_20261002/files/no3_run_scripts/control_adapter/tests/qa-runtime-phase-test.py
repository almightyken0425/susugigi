#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import time
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "programs/qa-runtime-phase.py"


class PhaseTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("phase", SCRIPT)
        self.phase = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.phase)
        self.token = "d" * 64
        self.identity = "a" * 64
        self.request = "bootstrap-" + "b" * 32
        self.ready = {"schema": "qa.runtime/v1", "requestId": self.request,
                      "state": "ready", "isAnonymous": True,
                      "identityMode": "disposable-anonymous", "identityHash": self.identity}
        self.proof = {"tokenHash": hashlib.sha256(self.token.encode()).hexdigest(),
                      "uidHash": self.identity, "expiresAt": 1100, "state": "active",
                      "consumedBindings": [], "consumedRequestHashes": []}

    def check(self, lines=None, **kwargs):
        return self.phase.validate_ready_window(
            lines if lines is not None else ["QA READY " + json.dumps(self.ready)],
            phase="bootstrap", request_id=self.request, token=self.token,
            expected_identity=None, proof=self.proof, now=1000, elapsed=1, **kwargs)

    def test_exact_ready_and_matching_native_proof(self):
        self.assertEqual(self.check(), self.identity)

    def test_system_python_39_clock_is_shared_between_processes(self):
        script = 'import time; print(time.clock_gettime(time.CLOCK_MONOTONIC_RAW))'
        first = float(subprocess.check_output(["/usr/bin/python3", "-I", "-c", script]))
        time.sleep(.2)
        second = float(subprocess.check_output(["/usr/bin/python3", "-I", "-c", script]))
        self.assertGreaterEqual(second - first, .2)
        self.assertLess(second - first, 5)

    def test_no_ready_is_pending(self):
        with self.assertRaises(self.phase.Pending):
            self.check([])

    def test_duplicate_ready_rejected(self):
        with self.assertRaises(self.phase.Invalid):
            self.check(["QA READY " + json.dumps(self.ready)] * 2)

    def test_other_request_cannot_fill_window(self):
        self.ready["requestId"] = "different-request"
        with self.assertRaises(self.phase.Invalid):
            self.check()

    def test_result_in_bootstrap_window_rejected(self):
        with self.assertRaises(self.phase.Invalid):
            self.check(["QA READY " + json.dumps(self.ready), "QA RESULT {}"])

    def test_safe_bootstrap_failure_reports_only_allowlisted_reason(self):
        failure = {"schema": "qa.runtime/v1", "requestId": self.request,
                   "operation": "bootstrap", "value": "identity",
                   "error": "QA_ANONYMOUS_BOOTSTRAP_FAILED"}
        line = "QA RESULT " + json.dumps(failure)
        with self.assertRaisesRegex(self.phase.ReportedFailure,
                                    "^QA_ANONYMOUS_BOOTSTRAP_FAILED$"):
            self.check([line])

        for key, value in (("requestId", "bootstrap-" + "c" * 32),
                           ("error", "PRIVATE_FAILURE_DETAIL")):
            with self.subTest(key=key):
                changed = dict(failure)
                changed[key] = value
                with self.assertRaises(self.phase.Invalid):
                    self.check(["QA RESULT " + json.dumps(changed)])

        with self.assertRaises(self.phase.Invalid):
            self.check([line, line])

    def test_open_app_failure_never_uses_bootstrap_reason_channel(self):
        request = "open-app-" + "c" * 32
        failure = {"schema": "qa.runtime/v1", "requestId": request,
                   "operation": "launch", "value": None,
                   "error": "QA_LAUNCH_FAILED"}
        with self.assertRaises(self.phase.Invalid):
            self.phase.validate_ready_window(
                ["QA RESULT " + json.dumps(failure)], phase="open-app",
                request_id=request, token=self.token, expected_identity=self.identity,
                proof=self.proof, now=1000, elapsed=1)

    def test_sentinel_after_ready_rejected(self):
        with self.assertRaises(self.phase.Invalid):
            self.check(["QA READY " + json.dumps(self.ready), "QA RUNTIME MARKER REJECTED"])

    def test_missing_hash_or_extra_private_field_rejected(self):
        for field, value in (("identityHash", "invalid"), ("uid", "private")):
            with self.subTest(field=field):
                self.ready[field] = value
                with self.assertRaises(self.phase.Invalid):
                    self.check()
                self.ready.pop(field)
                self.ready["identityHash"] = self.identity

    def test_wrong_token_identity_expiry_or_state_rejected(self):
        for key, value in (("tokenHash", "f" * 64), ("uidHash", "e" * 64),
                           ("expiresAt", 999), ("expiresAt", 100000),
                           ("state", "disposing"), ("expiresAt", True)):
            with self.subTest(key=key, value=value):
                original = self.proof[key]
                self.proof[key] = value
                with self.assertRaises(self.phase.Invalid):
                    self.check()
                self.proof[key] = original

    def test_open_app_requires_consumed_request_and_operation(self):
        request = "open-app-" + "b" * 32
        self.ready["requestId"] = request
        arguments = dict(phase="open-app", request_id=request, token=self.token,
                         expected_identity=self.identity, proof=self.proof, now=1000, elapsed=1)
        lines = ["QA READY " + json.dumps(self.ready)]
        with self.assertRaises(self.phase.Invalid):
            self.phase.validate_ready_window(lines, **arguments)
        self.proof["consumedBindings"] = [hashlib.sha256(b"open-app:true").hexdigest()]
        self.proof["consumedRequestHashes"] = [hashlib.sha256(request.encode()).hexdigest()]
        self.assertEqual(self.phase.validate_ready_window(lines, **arguments), self.identity)

    def test_deadline_is_not_extended_by_marker_arrival(self):
        with self.assertRaisesRegex(
            self.phase.Invalid, "^QA_READY_DEADLINE_EXCEEDED$",
        ):
            self.phase.validate_ready_window([], phase="bootstrap", request_id=self.request,
                                            token=self.token, expected_identity=None,
                                            proof=self.proof, now=1000, elapsed=31)

    def test_nonfinite_elapsed_is_input_failure_not_timeout(self):
        with self.assertRaisesRegex(
            self.phase.Invalid, "^QA_READY_INPUT_INVALID$",
        ):
            self.phase.validate_ready_window(
                [], phase="bootstrap", request_id=self.request,
                token=self.token, expected_identity=None, proof=self.proof,
                now=1000, elapsed=float("nan"),
            )

    def test_cleanup_accepts_expired_staged_proof_but_never_other_token(self):
        self.proof.update(state="staged", expiresAt=999)
        self.phase.validate_proof(self.proof, token=self.token, identity=self.identity,
                                  now=1000, cleanup=True)
        with self.assertRaises(self.phase.Invalid):
            self.phase.validate_proof(self.proof, token="b" * 64, identity=self.identity,
                                      now=1000, cleanup=True)
        with self.assertRaises(self.phase.Invalid):
            self.check()

    def test_prepare_result_is_exact_one_and_bound_to_request(self):
        request = "prepare-" + "b" * 32
        self.ready["requestId"] = request
        self.proof["consumedBindings"] = [hashlib.sha256(b"prepare:r02_end").hexdigest()]
        self.proof["consumedRequestHashes"] = [hashlib.sha256(request.encode()).hexdigest()]
        result = {"schema": "qa.runtime/v1", "requestId": request, "operation": "prepare",
                  "value": "r02_end", "result": {"ok": True, "runId": "qa-abcdefgh-1",
                  "value": {"sceneId": "r02_end", "fingerprint": "r02-end-v1"}}}
        result["result"]["value"]["fingerprint"] = self.phase._markers.SCENE_FINGERPRINTS["r02_end"]
        args = dict(phase="prepare", operation_value="r02_end", request_id=request,
                    token=self.token, expected_identity=self.identity, proof=self.proof,
                    now=1000, elapsed=1)
        lines = ["QA READY " + json.dumps(self.ready), "QA RESULT " + json.dumps(result)]
        self.assertEqual(self.phase.validate_operation_window(lines, **args), result["result"]["value"])
        for bad_lines in (lines + lines[1:], lines[:1], [lines[0], lines[1].replace(request, "wrong-request")]):
            with self.subTest(lines=bad_lines), self.assertRaises((self.phase.Invalid, self.phase.Pending)):
                self.phase.validate_operation_window(bad_lines, **args)

    def test_read_only_proof_reader_rejects_other_bundle_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            container = Path(temporary).resolve() / "data/Containers/Data/Application/ABC"
            proof_directory = container / "Library/Application Support/qa_runtime"
            proof_directory.mkdir(parents=True)
            metadata = container / ".com.apple.mobile_container_manager.metadata.plist"
            metadata.write_bytes(plistlib.dumps({"MCMMetadataIdentifier": self.phase.QA_BUNDLE}))
            path = proof_directory / "qa_session_proof_v1.plist"
            path.write_bytes(plistlib.dumps(self.proof))
            before = path.read_bytes()
            self.assertEqual(self.phase.read_qa_proof(container), self.proof)
            self.assertEqual(path.read_bytes(), before)
            metadata.write_bytes(plistlib.dumps({"MCMMetadataIdentifier": "production.bundle"}))
            with self.assertRaises(self.phase.Invalid):
                self.phase.read_qa_proof(container)
            metadata.write_bytes(plistlib.dumps({"MCMMetadataIdentifier": self.phase.QA_BUNDLE}))
            destination = path.with_suffix(".saved")
            path.rename(destination)
            path.symlink_to(destination)
            with self.assertRaises(self.phase.Invalid):
                self.phase.read_qa_proof(container)
            path.unlink()
            destination.rename(path)
            proof_directory.rename(container / "other")
            proof_directory.symlink_to(container / "other")
            with self.assertRaises(self.phase.Invalid):
                self.phase.read_qa_proof(container)

    def test_regular_reader_rejects_fifo_without_blocking(self):
        with tempfile.TemporaryDirectory() as temporary:
            fifo = Path(temporary) / "proof.plist"
            os.mkfifo(fifo)
            directory_fd = os.open(temporary, os.O_RDONLY | os.O_DIRECTORY)
            started = time.monotonic()
            try:
                with self.assertRaisesRegex(
                    self.phase.Invalid, "^QA_RUNTIME_FILE_INVALID$",
                ):
                    self.phase.read_regular_at(directory_fd, fifo.name)
            finally:
                os.close(directory_fd)
            self.assertLess(time.monotonic() - started, 1)

    def test_cli_classifies_marker_io_without_echoing_path_or_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "private-token.log"
            arguments = [
                os.sys.executable, "-I", str(SCRIPT), "--phase", "bootstrap",
                "--request-id", self.request, "--markers", str(missing),
                "--offset", "0", "--started", str(self.phase.clock_seconds()),
                "--data-container", "/not-read",
            ]
            secret = json.dumps({"token": self.token, "expectedIdentity": None})
            missing_result = subprocess.run(
                arguments, input=secret, text=True, capture_output=True)
            self.assertEqual(
                missing_result.stderr, "QA_RUNTIME_MARKER_UNREADABLE\n")
            self.assertNotIn("private-token", missing_result.stderr)

            invalid = Path(temporary) / "markers.log"
            invalid.write_bytes(b"\xffprivate-token\n")
            arguments[arguments.index(str(missing))] = str(invalid)
            invalid_result = subprocess.run(
                arguments, input=secret, text=True, capture_output=True)
            self.assertEqual(
                invalid_result.stderr,
                "QA_RUNTIME_MARKER_INVALID_ENCODING\n",
            )
            self.assertNotIn("private-token", invalid_result.stderr)

    def test_cli_reads_secrets_only_from_stdin_and_emits_fixed_failure(self):
        import subprocess
        result = subprocess.run([os.sys.executable, "-I", str(SCRIPT)],
                                input='{"token":"private-token"}', text=True,
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("private-token", result.stdout + result.stderr)

        malformed = subprocess.run(
            [os.sys.executable, "-I", str(SCRIPT), "--phase", "bootstrap",
             "--data-container", "/not-read"],
            input="{private-token", text=True, capture_output=True)
        self.assertEqual(malformed.returncode, 1)
        self.assertEqual(malformed.stderr, "QA_PHASE_INPUT_INVALID\n")
        self.assertNotIn("private-token", malformed.stdout + malformed.stderr)

    def test_cli_ready_phase_classifies_invalid_token_as_ready_input(self):
        result = subprocess.run(
            [os.sys.executable, "-I", str(SCRIPT), "--phase", "bootstrap",
             "--request-id", self.request, "--markers", "/not-read",
             "--offset", "0", "--started", str(self.phase.clock_seconds()),
             "--data-container", "/not-read"],
            input=json.dumps({"token": "private-token", "expectedIdentity": None}),
            text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "QA_READY_INPUT_INVALID\n")
        self.assertNotIn("private-token", result.stdout + result.stderr)

    def test_invalid_reason_is_allowlisted_and_unknown_detail_is_hidden(self):
        self.assertEqual(
            self.phase.safe_invalid_reason(self.phase.Invalid("QA_NATIVE_PROOF_INVALID")),
            "QA_NATIVE_PROOF_INVALID")
        self.assertEqual(
            self.phase.safe_invalid_reason(self.phase.Invalid("private-token raw-uid")),
            "QA_RUNTIME_PHASE_REJECTED")

    def test_cli_reports_missing_native_proof_without_container_details(self):
        with tempfile.TemporaryDirectory() as temporary:
            container = (Path(temporary).resolve()
                         / "data/Containers/Data/Application/ABC")
            proof_directory = container / "Library/Application Support/qa_runtime"
            proof_directory.mkdir(parents=True)
            (container / ".com.apple.mobile_container_manager.metadata.plist").write_bytes(
                plistlib.dumps({"MCMMetadataIdentifier": self.phase.QA_BUNDLE}))
            (proof_directory / "qa_session_proof_v1.plist").write_bytes(
                plistlib.dumps({}))
            marker = Path(temporary) / "markers.log"
            marker.write_text("QA READY " + json.dumps(self.ready) + "\n")
            result = subprocess.run(
                [os.sys.executable, "-I", str(SCRIPT), "--phase", "bootstrap",
                 "--request-id", self.request, "--markers", str(marker),
                 "--offset", "0", "--started", str(self.phase.clock_seconds()),
                 "--data-container", str(container)],
                input=json.dumps({"token": self.token, "expectedIdentity": None}),
                text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "QA_NATIVE_PROOF_INVALID\n")
        self.assertNotIn(str(container), result.stderr)

    def test_cli_emits_exact_safe_bootstrap_failure(self):
        failure = {"schema": "qa.runtime/v1", "requestId": self.request,
                   "operation": "bootstrap", "value": "identity",
                   "error": "QA_SESSION_PROOF_WRITE_FAILED"}
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "markers.log"
            marker.write_text("QA RESULT " + json.dumps(failure) + "\n")
            result = subprocess.run(
                [os.sys.executable, "-I", str(SCRIPT), "--phase", "bootstrap",
                 "--request-id", self.request, "--markers", str(marker),
                 "--offset", "0", "--started", str(self.phase.clock_seconds()),
                 "--data-container", "/not-read"],
                input=json.dumps({"token": self.token, "expectedIdentity": None}),
                text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "QA_SESSION_PROOF_WRITE_FAILED\n")


if __name__ == "__main__":
    unittest.main()
