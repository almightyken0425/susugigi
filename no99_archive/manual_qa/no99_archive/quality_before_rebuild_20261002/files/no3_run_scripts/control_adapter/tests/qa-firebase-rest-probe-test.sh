#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$TEST_ROOT" <<'PY'
import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile


root = pathlib.Path(sys.argv[1])


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


firestore = load("qa_firestore_read", root / "programs/qa-firestore-read.py")
auth = load("qa_firebase_auth_absence", root / "programs/qa-firebase-auth-absence.py")
snapshot = load("qa_repo_snapshot", pathlib.Path(os.environ["QA_CONTROL_TEST_ROOT"]) / "scripts/qa-repo-snapshot.py")

uid = "qa-session-user"
resolved = firestore.resolve_resource_path(
    "users/{QA_SESSION_UID}/transactions",
    uid,
)
assert resolved == "users/qa-session-user/transactions"

try:
    firestore.resolve_resource_path("users/arbitrary", uid)
except firestore.ProbeFailure:
    pass
else:
    raise AssertionError("arbitrary Firestore path accepted")

payload = {
    "name": "projects/susugigi-qa/databases/(default)/documents/users/qa-session-user",
    "fields": {"provider": {"stringValue": "anonymous"}},
}
normalized = firestore.normalized_payload(payload, uid)
assert uid not in str(normalized)
assert "[QA_SESSION_UID]" in str(normalized)
assert len(firestore.payload_digest(payload, uid)) == 64

identity_hash = hashlib.sha256(uid.encode("utf-8")).hexdigest()
assert auth.identity_match_count({"users": [{"localId": uid}]}, identity_hash) == 1
assert auth.identity_match_count({"users": [{"localId": "other"}]}, identity_hash) == 0

original_argv = firestore.sys.argv
try:
    firestore.sys.argv = [
        "qa-firestore-read.py",
        "--project",
        "susugigi-c4fb1",
        "--profile",
        "r01-user-anonymous",
    ]
    try:
        firestore.parse_arguments()
    except firestore.ProbeFailure:
        pass
    else:
        raise AssertionError("Production Firestore project accepted")
finally:
    firestore.sys.argv = original_argv

try:
    auth.verify_absent("susugigi-c4fb1", identity_hash)
except auth.ProbeFailure:
    pass
else:
    raise AssertionError("Production Auth project accepted")

try:
    auth.identity_match_count({"users": [{"email": "unsafe@example.invalid"}]}, identity_hash)
except auth.ProbeFailure:
    pass
else:
    raise AssertionError("Auth response without localId accepted")

assert snapshot.utf16_key("a") < snapshot.utf16_key("b")

with tempfile.TemporaryDirectory() as snapshot_test_root:
    snapshot_test_root = pathlib.Path(snapshot_test_root).resolve()
    repository = pathlib.Path(snapshot_test_root) / "repository"
    repository.mkdir()
    subprocess.run(["git", "-C", repository, "init", "-q"], check=True)
    (repository / "tracked.txt").write_text("one\n", encoding="utf-8")
    subprocess.run(["git", "-C", repository, "add", "tracked.txt"], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            repository,
            "-c",
            "user.name=QA Test",
            "-c",
            "user.email=qa-test@example.invalid",
            "commit",
            "-qm",
            "fixture",
        ],
        check=True,
    )
    clean_snapshot = snapshot.snapshot_payload(
        repository,
        "fixture-repository",
        "control-plane-snapshot/v1",
    )
    (repository / "tracked.txt").write_text("two\n", encoding="utf-8")
    tracked_snapshot = snapshot.snapshot_payload(
        repository,
        "fixture-repository",
        "control-plane-snapshot/v1",
    )
    assert tracked_snapshot != clean_snapshot
    (repository / "untracked.txt").write_text("three\n", encoding="utf-8")
    untracked_snapshot = snapshot.snapshot_payload(
        repository,
        "fixture-repository",
        "control-plane-snapshot/v1",
    )
    assert untracked_snapshot != tracked_snapshot
    linked_repository = pathlib.Path(snapshot_test_root) / "linked-repository"
    os.symlink(repository, linked_repository)
    rejected = subprocess.run(
        [sys.executable, "-I", str(pathlib.Path(os.environ["QA_CONTROL_TEST_ROOT"]) / "scripts/qa-repo-snapshot.py"),
         "--repo", str(linked_repository), "--repository", "fixture-repository",
         "--schema", "control-plane-snapshot/v1"],
        capture_output=True, text=True,
    )
    assert rejected.returncode != 0
    assert rejected.stdout == ""
    assert rejected.stderr == "QA_REPO_SNAPSHOT_FAILED\n"


class FakeResponse:
    def __init__(self, payload):
        self.status = 200
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, _type, _value, _traceback):
        return False

    def read(self, _limit):
        return self.payload


class FakeFailureResponse(FakeResponse):
    def read(self, limit):
        super().read(limit)
        raise OSError("synthetic response failure")


class FakeOpener:
    def __init__(self, response):
        self.response = response

    def open(self, _request, timeout):
        assert timeout == 30
        return self.response


original_build_opener = firestore.urllib.request.build_opener
try:
    with tempfile.TemporaryDirectory() as private_test_root:
        firestore.urllib.request.build_opener = lambda *_handlers: FakeOpener(
            FakeResponse(b'{"fields":{}}')
        )
        status, response = firestore.request_json(
            "https://firestore.googleapis.com/v1/projects/susugigi-qa",
            "token",
        )
        assert status == 200
        assert response == {"fields": {}}
        assert list(pathlib.Path(private_test_root).iterdir()) == []
        firestore.urllib.request.build_opener = lambda *_handlers: FakeOpener(
            FakeFailureResponse(b'{"fields":{}}')
        )
        try:
            firestore.request_json(
                "https://firestore.googleapis.com/v1/projects/susugigi-qa",
                "token",
            )
        except firestore.ProbeFailure:
            pass
        else:
            raise AssertionError("Firestore response failure accepted")
        assert list(pathlib.Path(private_test_root).iterdir()) == []
        try:
            firestore.request_json("https://example.invalid", "token")
        except firestore.ProbeFailure:
            pass
        else:
            raise AssertionError("non-Firestore host accepted")
finally:
    firestore.urllib.request.build_opener = original_build_opener

for invalid_fields in (
    {1: {"stringValue": "unsafe"}},
    {"x" * 129: {"stringValue": "unsafe"}},
):
    try:
        firestore.decode_firestore_value({"mapValue": {"fields": invalid_fields}})
    except firestore.ProbeFailure:
        pass
    else:
        raise AssertionError("invalid Firestore map key accepted")

PY

echo 'qa-firebase-rest-probe tests passed'
