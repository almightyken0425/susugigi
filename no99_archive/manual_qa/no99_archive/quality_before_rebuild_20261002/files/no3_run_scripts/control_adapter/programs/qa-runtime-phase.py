#!/usr/bin/env python3
"""驗證已過濾的 READY window。秘密輸入與成功 hash 僅走父程序 pipe。"""
import hashlib
import hmac
import importlib.util
import argparse
import json
import math
import os
from pathlib import Path
import plistlib
import re
import stat
import sys
import time

_spec = importlib.util.spec_from_file_location(
    "qa_safe_marker_filter", Path(__file__).with_name("qa-safe-marker-filter.py"))
_markers = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_markers)
HEX = re.compile(r"[0-9a-f]{64}\Z")
PROOF_KEYS = {"tokenHash", "uidHash", "expiresAt", "state",
              "consumedBindings", "consumedRequestHashes"}
QA_BUNDLE = "com.almightyken0425.susugigiapp.qa"
GENERIC_REJECTION = "QA_RUNTIME_PHASE_REJECTED"
SAFE_INVALID_REASONS = frozenset(
    {
        "QA_BOOTSTRAP_PROOF_ALREADY_CONSUMED",
        "QA_MARKER_OFFSET_INVALID",
        "QA_NATIVE_CONTAINER_BUNDLE_MISMATCH",
        "QA_NATIVE_CONTAINER_INVALID",
        "QA_NATIVE_PROOF_CONSUMPTION_INVALID",
        "QA_NATIVE_PROOF_INVALID",
        "QA_NATIVE_PROOF_MISMATCH",
        "QA_NATIVE_PROOF_UNREADABLE",
        "QA_OPEN_APP_PROOF_BINDING_MISMATCH",
        "QA_OPEN_APP_PROOF_MISMATCH",
        "QA_OPERATION_INVALID",
        "QA_PHASE_INPUT_INVALID",
        "QA_READY_DEADLINE_EXCEEDED",
        "QA_READY_INPUT_INVALID",
        "QA_READY_INVALID",
        "QA_READY_NOT_EXACT_ONE",
        "QA_READY_REQUEST_MISMATCH",
        "QA_READY_WINDOW_REJECTED",
        "QA_RESULT_DEADLINE_INVALID",
        "QA_RESULT_FACT_FAILED",
        "QA_RESULT_FAILED",
        "QA_RESULT_INVALID",
        "QA_RESULT_MISMATCH",
        "QA_RESULT_NOT_EXACT_ONE",
        "QA_RESULT_NOT_FILTERED",
        "QA_RUNTIME_FILE_INVALID",
        "QA_RUNTIME_FILE_TOO_LARGE",
        "QA_RUNTIME_MARKER_INVALID_ENCODING",
        "QA_RUNTIME_MARKER_UNREADABLE",
        "QA_RUNTIME_MARKER_SESSION_TAINTED",
    }
)


def clock_seconds():
    return time.clock_gettime(time.CLOCK_MONOTONIC_RAW)


class Invalid(ValueError):
    pass


class Pending(Exception):
    pass


class ReportedFailure(Exception):
    """已通過 marker filter，可安全回報的固定 bootstrap 失敗碼。"""


def safe_invalid_reason(error):
    reason = str(error)
    return reason if reason in SAFE_INVALID_REASONS else GENERIC_REJECTION


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def valid_hash(value):
    return isinstance(value, str) and HEX.fullmatch(value) is not None


def validate_proof(proof, *, token, identity, now, cleanup=False):
    if not isinstance(proof, dict) or set(proof) != PROOF_KEYS:
        raise Invalid("QA_NATIVE_PROOF_INVALID")
    expiry = proof["expiresAt"]
    if (not valid_hash(token) or not valid_hash(identity)
            or not valid_hash(proof["tokenHash"]) or not valid_hash(proof["uidHash"])
            or type(expiry) not in (int, float) or not math.isfinite(expiry)
            or not 0 < expiry <= now + 28800 or (not cleanup and expiry <= now)
            or proof["state"] not in (("active", "staged", "disposing") if cleanup else ("active",))
            or not hmac.compare_digest(proof["tokenHash"], digest(token))
            or not hmac.compare_digest(proof["uidHash"], identity)):
        raise Invalid("QA_NATIVE_PROOF_MISMATCH")
    bindings, requests = proof["consumedBindings"], proof["consumedRequestHashes"]
    if (not isinstance(bindings, list) or not isinstance(requests, list)
            or len(bindings) != len(requests) or len(bindings) > 256
            or not all(valid_hash(value) for value in bindings + requests)
            or len(set(requests)) != len(requests)):
        raise Invalid("QA_NATIVE_PROOF_CONSUMPTION_INVALID")


def validate_ready_window(lines, *, phase, request_id, token, expected_identity,
                          proof, now, elapsed, operation_value="true"):
    if (phase not in ("bootstrap", "first-launch", "first-home", "open-app", "prepare", "inspect")
            or not _markers.valid_request_id(request_id)
            or not valid_hash(token) or not math.isfinite(elapsed)):
        raise Invalid("QA_READY_INPUT_INVALID")
    if not 0 <= elapsed <= (600 if phase == "first-launch" else 30):
        raise Invalid("QA_READY_DEADLINE_EXCEEDED")
    ready = []
    bootstrap_failures = []
    for line in lines:
        if line == _markers.RUNTIME_MARKER_REJECTION_SENTINEL:
            raise Invalid("QA_READY_WINDOW_REJECTED")
        if line.startswith("QA RESULT") and phase in ("bootstrap", "first-launch", "first-home", "open-app"):
            if phase in ("first-launch", "first-home"):
                safe = _markers.safe_result_line(line)
                payload = _markers.parse_runtime_payload(safe, "QA RESULT ") if safe else None
                if (payload and payload.get("requestId") == request_id
                        and payload.get("operation") == "launch"
                        and payload.get("error") in _markers.SAFE_OPERATION_ERRORS["launch"]):
                    raise ReportedFailure(payload["error"])
            if phase != "bootstrap":
                raise Invalid("QA_READY_WINDOW_REJECTED")
            safe = _markers.safe_result_line(line)
            payload = (_markers.parse_runtime_payload(safe, "QA RESULT ")
                       if safe is not None else None)
            if (payload is None or payload.get("requestId") != request_id
                    or payload.get("operation") != "bootstrap"
                    or payload.get("value") != "identity"
                    or payload.get("error") not in _markers.SAFE_OPERATION_ERRORS["bootstrap"]):
                raise Invalid("QA_READY_WINDOW_REJECTED")
            bootstrap_failures.append(payload["error"])
        if line.startswith("QA READY"):
            safe = _markers.safe_ready_line(line)
            if safe is None:
                raise Invalid("QA_READY_INVALID")
            payload = _markers.parse_runtime_payload(safe, "QA READY ")
            if payload["requestId"] != request_id:
                raise Invalid("QA_READY_REQUEST_MISMATCH")
            ready.append(payload)
    if len(ready) > 1:
        raise Invalid("QA_READY_NOT_EXACT_ONE")
    if len(bootstrap_failures) > 1:
        raise Invalid("QA_READY_WINDOW_REJECTED")
    if bootstrap_failures:
        raise ReportedFailure(bootstrap_failures[0])
    if not ready:
        raise Pending()
    identity = ready[0]["identityHash"]
    if phase in ("first-launch", "first-home"):
        if (not request_id.startswith("first-launch-")
                or lines.count("QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY") != 1
                or lines.count("QA NATIVE AUTH_NETWORK_RESTORED") != 1
                or lines.count("QA NATIVE AUTH_NETWORK_BLOCKED") < 2
                or lines.count("QA BOOT anonymous signIn start") != 3):
            raise Invalid("QA_READY_WINDOW_REJECTED")
        restore_index = lines.index("QA NATIVE AUTH_NETWORK_RESTORED")
        if any(line == "QA NATIVE AUTH_NETWORK_BLOCKED" for line in lines[restore_index + 1:]):
            raise Invalid("QA_READY_WINDOW_REJECTED")
    validate_proof(proof, token=token, identity=identity, now=now)
    if phase in ("bootstrap", "first-launch"):
        if phase == "first-launch" and not request_id.startswith("first-launch-"):
            raise Invalid("QA_READY_REQUEST_MISMATCH")
        if proof["consumedBindings"] or proof["consumedRequestHashes"]:
            raise Invalid("QA_BOOTSTRAP_PROOF_ALREADY_CONSUMED")
    else:
        binding = digest(("first-launch" if phase == "first-home" else phase) + ":" + operation_value)
        if (not valid_hash(expected_identity)
                or not hmac.compare_digest(identity, expected_identity)
                or digest(request_id) not in proof["consumedRequestHashes"]
                or binding not in proof["consumedBindings"]):
            raise Invalid("QA_OPEN_APP_PROOF_MISMATCH")
        index = proof["consumedRequestHashes"].index(digest(request_id))
        if proof["consumedBindings"][index] != binding:
            raise Invalid("QA_OPEN_APP_PROOF_BINDING_MISMATCH")
    if phase == "first-home":
        home = "QA BOOT resolve premiumLoaded=true landing=sha256:" + digest("home")
        if lines.count(home) == 0:
            raise Pending()
        if lines.count(home) != 1:
            raise Invalid("QA_READY_WINDOW_REJECTED")
    return identity


def validate_operation_window(lines, *, phase, operation_value, request_id, token,
                              expected_identity, proof, now, elapsed, ready_only=False):
    allowed = _markers.SCENE_FINGERPRINTS if phase == "prepare" else _markers.CHECK_FACT_KEYS
    if phase not in ("prepare", "inspect") or operation_value not in allowed:
        raise Invalid("QA_OPERATION_INVALID")
    identity = validate_ready_window(lines, phase=phase, operation_value=operation_value,
                                     request_id=request_id, token=token, expected_identity=expected_identity,
                                     proof=proof, now=now, elapsed=elapsed)
    results = []
    for line in lines:
        if not line.startswith("QA RESULT"):
            continue
        if _markers.safe_result_line(line, identity) is None:
            raise Invalid("QA_RESULT_INVALID")
        payload = _markers.parse_runtime_payload(line, "QA RESULT ")
        if (payload["requestId"] != request_id or payload["operation"] != phase
                or payload["value"] != operation_value or "error" in payload
                or payload["result"].get("ok") is not True):
            raise Invalid("QA_RESULT_MISMATCH")
        value = payload["result"]["value"]
        if phase == "inspect":
            if value["verdict"] != "pass":
                raise Invalid("QA_RESULT_FAILED")
            for fact in value["facts"]:
                if fact.get("pass") is not True:
                    raise Invalid("QA_RESULT_FACT_FAILED")
                for key in ("actual", "expected"):
                    if isinstance(fact.get(key), str) and not re.fullmatch(r"sha256:[0-9a-f]{64}", fact[key]):
                        raise Invalid("QA_RESULT_NOT_FILTERED")
        results.append(value)
    if len(results) > 1:
        raise Invalid("QA_RESULT_NOT_EXACT_ONE")
    if ready_only:
        return identity
    if not results:
        raise Pending()
    return results[0]


def read_regular_at(directory_fd, name, limit=1048576):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                 dir_fd=directory_fd)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise Invalid("QA_RUNTIME_FILE_INVALID")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise Invalid("QA_RUNTIME_FILE_TOO_LARGE")
        return data


def read_qa_proof(container):
    container = Path(container)
    if (not container.is_absolute() or str(container.resolve()) != str(container)
            or container.parts[-5:-1] != ("data", "Containers", "Data", "Application")):
        raise Invalid("QA_NATIVE_CONTAINER_INVALID")
    descriptors = []
    try:
        fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
        descriptors.append(fd)
        for component in container.parts[1:]:
            fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            descriptors.append(fd)
        metadata = plistlib.loads(read_regular_at(fd, ".com.apple.mobile_container_manager.metadata.plist"))
        if not isinstance(metadata, dict) or metadata.get("MCMMetadataIdentifier") != QA_BUNDLE:
            raise Invalid("QA_NATIVE_CONTAINER_BUNDLE_MISMATCH")
        for component in ("Library", "Application Support", "qa_runtime"):
            fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            descriptors.append(fd)
        proof = plistlib.loads(read_regular_at(fd, "qa_session_proof_v1.plist"))
        if not isinstance(proof, dict):
            raise Invalid("QA_NATIVE_PROOF_INVALID")
        return proof
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise Invalid("QA_NATIVE_PROOF_UNREADABLE") from None
    finally:
        for fd in reversed(descriptors):
            os.close(fd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", required=True, choices=("bootstrap", "first-launch", "first-home", "open-app", "cleanup", "authorize", "prepare", "inspect"))
    parser.add_argument("--operation-value", default="true")
    parser.add_argument("--check", choices=("ready", "complete"), default="ready")
    parser.add_argument("--ready-elapsed", type=float)
    parser.add_argument("--ready-at", type=float)
    parser.add_argument("--request-id")
    parser.add_argument("--markers")
    parser.add_argument("--offset", type=int)
    parser.add_argument("--started", type=float)
    parser.add_argument("--data-container", required=True)
    args = parser.parse_args()
    try:
        try:
            secret = json.loads(sys.stdin.buffer.read(4097))
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise Invalid("QA_PHASE_INPUT_INVALID") from None
        if not isinstance(secret, dict) or set(secret) != {"token", "expectedIdentity"}:
            raise Invalid("QA_PHASE_INPUT_INVALID")
        if not valid_hash(secret["token"]):
            reason = ("QA_READY_INPUT_INVALID"
                      if args.phase in ("bootstrap", "open-app", "prepare", "inspect")
                      else "QA_PHASE_INPUT_INVALID")
            raise Invalid(reason)
        if args.phase in ("cleanup", "authorize"):
            proof = read_qa_proof(args.data_container)
            if not isinstance(proof, dict):
                raise Invalid("QA_NATIVE_PROOF_INVALID")
            identity = proof.get("uidHash")
            validate_proof(proof, token=secret["token"], identity=identity, now=time.time(), cleanup=args.phase == "cleanup")
            if args.phase == "authorize" and not valid_hash(secret["expectedIdentity"]):
                raise Invalid("QA_NATIVE_PROOF_MISMATCH")
            if (secret["expectedIdentity"] is not None
                    and secret["expectedIdentity"] != identity):
                raise Invalid("QA_NATIVE_PROOF_MISMATCH")
            sys.stdout.write(identity)
            return 0
        if any(value is None for value in (args.request_id, args.markers, args.offset, args.started)):
            raise Invalid("QA_PHASE_INPUT_INVALID")
        marker_path = Path(args.markers)
        try:
            fd = os.open(str(marker_path.parent), os.O_RDONLY | os.O_DIRECTORY
                         | os.O_NOFOLLOW | os.O_CLOEXEC)
            try:
                data = read_regular_at(fd, marker_path.name, 16 * 1048576)
            finally:
                os.close(fd)
        except OSError:
            raise Invalid("QA_RUNTIME_MARKER_UNREADABLE") from None
        try:
            lines = data.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            raise Invalid("QA_RUNTIME_MARKER_INVALID_ENCODING") from None
        if args.offset < 0 or args.offset > len(lines):
            raise Invalid("QA_MARKER_OFFSET_INVALID")
        if _markers.RUNTIME_MARKER_REJECTION_SENTINEL in lines:
            raise Invalid("QA_RUNTIME_MARKER_SESSION_TAINTED")
        elapsed = clock_seconds() - args.started
        if args.phase in ("prepare", "inspect") and args.check == "complete":
            if args.ready_at is None or args.ready_elapsed is None or not 0 <= clock_seconds() - args.ready_at <= 120:
                raise Invalid("QA_RESULT_DEADLINE_INVALID")
            elapsed = args.ready_elapsed
        if not math.isfinite(elapsed):
            raise Invalid("QA_READY_INPUT_INVALID")
        if not 0 <= elapsed <= (600 if args.phase == "first-launch" else 30):
            raise Invalid("QA_READY_DEADLINE_EXCEEDED")
        if data and not data.endswith(b"\n"):
            raise Pending()
        window = lines[args.offset:]
        proof = read_qa_proof(args.data_container) if any(
            line.startswith("QA READY") for line in window) else None
        if args.phase in ("prepare", "inspect"):
            value = validate_operation_window(window, phase=args.phase, operation_value=args.operation_value,
                                               request_id=args.request_id, token=secret["token"],
                                               expected_identity=secret["expectedIdentity"], proof=proof,
                                               now=time.time(), elapsed=elapsed, ready_only=args.check == "ready")
            sys.stdout.write(value if isinstance(value, str) else json.dumps(value, separators=(",", ":")))
            return 0
        identity = validate_ready_window(window, phase=args.phase, request_id=args.request_id,
                                         token=secret["token"], expected_identity=secret["expectedIdentity"],
                                         proof=proof, now=time.time(), elapsed=elapsed)
        sys.stdout.write(identity)
        return 0
    except Pending:
        return 42
    except ReportedFailure as error:
        sys.stderr.write(str(error) + "\n")
        return 1
    except Invalid as error:
        sys.stderr.write(safe_invalid_reason(error) + "\n")
        return 1
    except (OSError, ValueError, TypeError, OverflowError):
        sys.stderr.write(GENERIC_REJECTION + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
