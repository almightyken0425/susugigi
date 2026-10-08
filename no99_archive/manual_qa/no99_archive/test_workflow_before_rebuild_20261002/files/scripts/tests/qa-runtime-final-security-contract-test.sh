#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIM_REVIEW="$(mktemp)"
trap 'rm -f "$SIM_REVIEW"' EXIT
python3 -B "$CONTROL_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" > "$SIM_REVIEW"
AUTH_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py"
FIRESTORE_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firestore-read.py"
SNAPSHOT_PROBE="$CONTROL_ROOT/scripts/qa-repo-snapshot.py"
SAFE_CHILD_ENV="$CONTROL_ROOT/scripts/qa-safe-child-env.py"
PYTHON_BIN="$(command -v python3)"
PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

require_literal() {
  local description="$1"
  local file="$2"
  local literal="$3"

  if grep -Fq -- "$literal" "$file"; then
    pass
  else
    fail "$description"
  fi
}

reject_literal() {
  local description="$1"
  local file="$2"
  local literal="$3"

  if grep -Fq -- "$literal" "$file"; then
    fail "$description"
  else
    pass
  fi
}

for variable_name in \
  CLOUDSDK_PROXY_TYPE \
  CLOUDSDK_PROXY_ADDRESS \
  CLOUDSDK_PROXY_PORT \
  CLOUDSDK_PROXY_USERNAME \
  CLOUDSDK_PROXY_PASSWORD \
  CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
  NO_PROXY \
  no_proxy \
  SSL_CERT_FILE \
  SSL_CERT_DIR \
  REQUESTS_CA_BUNDLE \
  CURL_CA_BUNDLE \
  NODE_EXTRA_CA_CERTS \
  NODE_TLS_REJECT_UNAUTHORIZED \
  npm_config_proxy \
  npm_config_https_proxy \
  npm_config_cafile \
  PYTHONPATH \
  PYTHONHOME \
  PYTHONSTARTUP \
  PYTHONINSPECT \
  BASH_ENV \
  ENV \
  BASH_XTRACEFD \
  PS4 \
  NODE_OPTIONS \
  NODE_PATH \
  SSLKEYLOGFILE \
  DYLD_INSERT_LIBRARIES \
  DYLD_LIBRARY_PATH \
  LD_PRELOAD \
  LD_LIBRARY_PATH; do
  require_literal "Auth probe must reject $variable_name" "$AUTH_PROBE" "$variable_name"
  require_literal "Firestore probe must reject $variable_name" "$FIRESTORE_PROBE" "$variable_name"
  require_literal "runner must reject $variable_name" "$SIM_REVIEW" "$variable_name"
done

require_literal 'Firestore must inspect local gcloud configuration before token use' \
  "$FIRESTORE_PROBE" 'validate_gcloud_local_config('
require_literal 'Auth must inspect local Firebase configuration before export' \
  "$AUTH_PROBE" 'validate_firebase_local_config('
require_literal 'Firestore response must be parsed in memory' \
  "$FIRESTORE_PROBE" 'json.loads(response_bytes)'
reject_literal 'Firestore response must never be persisted' \
  "$FIRESTORE_PROBE" 'qa-firestore-response-'
reject_literal 'runtime Python helpers must not inherit import-path injection' \
  "$SIM_REVIEW" 'python3 "$SESSION_'
require_literal 'runtime Python helpers must use isolated mode' \
  "$SIM_REVIEW" 'python3 -I "$SESSION_'
require_literal 'runtime commands must cross the checked-in child environment guard' \
  "$SIM_REVIEW" 'python3 -I "$SESSION_CONTROL_PLANE_ROOT/scripts/qa-safe-child-env.py"'
require_literal 'runtime outer shell must reject BASH_ENV before helper launch' \
  "$SIM_REVIEW" 'BASH_ENV'
require_literal 'runtime child environment guard must reject BASH_ENV' \
  "$SAFE_CHILD_ENV" '"BASH_ENV"'
require_literal 'runtime child environment guard must reject Bash xtrace descriptors' \
  "$SAFE_CHILD_ENV" '"BASH_XTRACEFD"'
require_literal 'runtime child environment guard must reject exported Bash functions' \
  "$SAFE_CHILD_ENV" 'name.startswith("BASH_FUNC_")'
require_literal 'runtime child environment guard must pin the system PATH' \
  "$SAFE_CHILD_ENV" 'QA_TRUSTED_SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"'
require_literal 'runtime outer shell must scan exported Bash function variables' \
  "$SIM_REVIEW" 'BASH_FUNC_*'
require_literal 'runtime outer shell must invoke the environment binary absolutely' \
  "$SIM_REVIEW" '/usr/bin/env \'
require_literal 'runtime snapshot wrapper must invoke Python absolutely' \
  "$SIM_REVIEW" '/usr/bin/python3 -I "$SESSION_CONTROL_PLANE_ROOT/scripts/qa-safe-child-env.py"'
require_literal 'trusted Git must use its system absolute path' \
  "$SIM_REVIEW" '/usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT"'
require_literal 'trusted plist checks must use the system absolute path' \
  "$SIM_REVIEW" '/usr/bin/plutil -extract CFBundleIdentifier'
require_literal 'trusted digests must use the system absolute path' \
  "$SIM_REVIEW" '/usr/bin/shasum -a 256'
require_literal 'runtime child environment guard must clear exported SHELLOPTS' \
  "$SAFE_CHILD_ENV" 'QA_CLEAR_ONLY_ENV = frozenset({"SHELLOPTS", "BASHOPTS"})'
reject_literal 'normally nonempty SHELLOPTS must not be an unconditional rejection' \
  "$SAFE_CHILD_ENV" '        "SHELLOPTS",'

require_literal 'trusted manifest must bind topology' \
  "$SNAPSHOT_PROBE" 'def tree_manifest('
require_literal 'trusted manifest must bind mode' \
  "$SNAPSHOT_PROBE" '"mode"'
require_literal 'trusted manifest must bind link count' \
  "$SNAPSHOT_PROBE" '"linkCount"'
require_literal 'runner must use trusted tree manifest' \
  "$SIM_REVIEW" '--tree-manifest "$qa_session_tree_root"'
require_literal 'source copy must use trusted regular-file copier' \
  "$SIM_REVIEW" '--copy-regular-file'
require_literal 'trusted verifier must remain non-writable' \
  "$SIM_REVIEW" '[ ! -w "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" ]'

R13_BIND_BLOCK="$(sed -n \
  '/^prepare_r13_fixture_cleanup_binding_if_required() {/,/^}/p' \
  "$SIM_REVIEW")"
MOUNT_BIND_BLOCK="$(sed -n \
  '/^acquire_qa_app_mount_cleanup_ownership() {/,/^}/p' \
  "$SIM_REVIEW")"
if grep -Fq 'bind_qa_session_uid_from_auth_export || return 1' <<< "$MOUNT_BIND_BLOCK" \
  && grep -Fq 'FIXTURE_CLEANUP_REQUIRED=1' <<< "$MOUNT_BIND_BLOCK" \
  && ! grep -Fq 'run_and_validate_qa_open_app_operation' <<< "$R13_BIND_BLOCK" \
  && ! grep -Fq 'bind_qa_session_uid_from_sqlite' <<< "$R13_BIND_BLOCK"; then
  pass
else
  fail 'R13 pre-seed bind must use Auth export without open-app or SQLite'
fi
require_literal 'R13 must cross-check SQLite UID only after prepare' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" 'verify_r13_prepared_sqlite_identity || return 1'

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/.config/configstore"
cat > "$TEST_ROOT/bin/firebase" <<'FIREBASE_STUB'
#!/usr/bin/env bash
printf x > "$QA_NETWORK_CHILD_WAS_RUN"
printf '%s\n' SECRET_SENTINEL >&2
exit 99
FIREBASE_STUB
cat > "$TEST_ROOT/bin/gcloud" <<'GCLOUD_STUB'
#!/usr/bin/env bash
if [ "${1:-}" = config ]; then
  if [ "${QA_GCLOUD_CONFIG_MODE:-}" = safe ]; then
    printf '%s\n' '{}'
    exit 0
  fi
  printf '%s\n' '{"proxy":{"address":"attacker.invalid"}}'
  exit 0
fi
printf x > "$QA_NETWORK_CHILD_WAS_RUN"
printf '%s\n' SECRET_SENTINEL >&2
exit 99
GCLOUD_STUB
chmod 700 "$TEST_ROOT/bin/firebase" "$TEST_ROOT/bin/gcloud"

for variable_name in BASH_ENV NODE_OPTIONS SSLKEYLOGFILE; do
  : > "$TEST_ROOT/child-$variable_name"
  if printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    | env \
        "$variable_name=attacker-value" \
        PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
        HOME="$TEST_ROOT/home" \
        QA_NETWORK_CHILD_WAS_RUN="$TEST_ROOT/child-$variable_name" \
        "$PYTHON_BIN" -I "$AUTH_PROBE" --project susugigi-qa \
        > "$TEST_ROOT/$variable_name.out" \
        2> "$TEST_ROOT/$variable_name.err"; then
    fail "$variable_name injection must fail closed"
  elif [ ! -s "$TEST_ROOT/child-$variable_name" ] \
    && grep -Fxq QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED \
      "$TEST_ROOT/$variable_name.err"; then
    pass
  else
    fail "$variable_name must be rejected before Firebase child execution"
  fi
done

printf '%s\n' '{"proxy":"https://attacker.invalid"}' \
  > "$TEST_ROOT/home/.config/configstore/firebase-tools.json"
: > "$TEST_ROOT/firebase-config-child"
if printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  | env \
      PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
      HOME="$TEST_ROOT/home" \
      QA_NETWORK_CHILD_WAS_RUN="$TEST_ROOT/firebase-config-child" \
      "$PYTHON_BIN" -I "$AUTH_PROBE" --project susugigi-qa \
      > "$TEST_ROOT/firebase-config.out" \
      2> "$TEST_ROOT/firebase-config.err"; then
  fail 'Firebase local proxy configuration must fail closed'
elif [ ! -s "$TEST_ROOT/firebase-config-child" ] \
  && grep -Fxq QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED \
    "$TEST_ROOT/firebase-config.err"; then
  pass
else
  fail 'Firebase local proxy config must be rejected before Auth export'
fi
rm "$TEST_ROOT/home/.config/configstore/firebase-tools.json"

: > "$TEST_ROOT/firebase-stderr-child"
if printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  | env \
      PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
      HOME="$TEST_ROOT/home" \
      QA_NETWORK_CHILD_WAS_RUN="$TEST_ROOT/firebase-stderr-child" \
      "$PYTHON_BIN" -I "$AUTH_PROBE" --project susugigi-qa \
      > "$TEST_ROOT/firebase-stderr.out" \
      2> "$TEST_ROOT/firebase-stderr.err"; then
  fail 'failed Firebase export must fail closed'
elif [ -s "$TEST_ROOT/firebase-stderr-child" ] \
  && grep -Fxq QA_AUTH_ABSENCE_PROBE_FAILED "$TEST_ROOT/firebase-stderr.err" \
  && ! grep -Fq SECRET_SENTINEL "$TEST_ROOT/firebase-stderr.out" \
  && ! grep -Fq SECRET_SENTINEL "$TEST_ROOT/firebase-stderr.err"; then
  pass
else
  fail 'Firebase CLI stderr must be discarded behind a fixed error code'
fi

: > "$TEST_ROOT/gcloud-token-child"
if printf '%s\n' qaSessionUid \
  | env \
      PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
      HOME="$TEST_ROOT/home" \
      QA_NETWORK_CHILD_WAS_RUN="$TEST_ROOT/gcloud-token-child" \
      "$PYTHON_BIN" -I "$FIRESTORE_PROBE" \
        --project susugigi-qa \
        --profile r01-user-anonymous \
      > "$TEST_ROOT/gcloud-config.out" \
      2> "$TEST_ROOT/gcloud-config.err"; then
  fail 'gcloud local proxy configuration must fail closed'
elif [ ! -s "$TEST_ROOT/gcloud-token-child" ] \
  && grep -Fxq QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED \
    "$TEST_ROOT/gcloud-config.err"; then
  pass
else
  fail 'gcloud local proxy config must be rejected before token or HTTP use'
fi

: > "$TEST_ROOT/gcloud-stderr-child"
if printf '%s\n' qaSessionUid \
  | env \
      PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
      HOME="$TEST_ROOT/home" \
      QA_GCLOUD_CONFIG_MODE=safe \
      QA_NETWORK_CHILD_WAS_RUN="$TEST_ROOT/gcloud-stderr-child" \
      "$PYTHON_BIN" -I "$FIRESTORE_PROBE" \
        --project susugigi-qa \
        --profile r01-user-anonymous \
      > "$TEST_ROOT/gcloud-stderr.out" \
      2> "$TEST_ROOT/gcloud-stderr.err"; then
  fail 'failed gcloud token read must fail closed'
elif [ -s "$TEST_ROOT/gcloud-stderr-child" ] \
  && grep -Fxq QA_FIRESTORE_PROBE_FAILED "$TEST_ROOT/gcloud-stderr.err" \
  && ! grep -Fq SECRET_SENTINEL "$TEST_ROOT/gcloud-stderr.out" \
  && ! grep -Fq SECRET_SENTINEL "$TEST_ROOT/gcloud-stderr.err"; then
  pass
else
  fail 'gcloud stderr must be discarded behind a fixed error code'
fi

R08_ORIGINAL_BLOCK="$(sed -n \
  '/^capture_r08_original_language_before_manual_changes() {/,/^}/p' \
  "$SIM_REVIEW")"
R08_UPDATED_BLOCK="$(sed -n \
  '/^capture_r08_cs01_updated_at_baseline() {/,/^}/p' \
  "$SIM_REVIEW")"
if grep -Fq 'profile r08_original_language' <<< "$R08_ORIGINAL_BLOCK" \
  && grep -Fq '"$SESSION_QUALITY_ROOT/no2_qa_tools/query_local_db.sh"' <<< "$R08_ORIGINAL_BLOCK" \
  && ! grep -Fq 'qa_firestore_read_driver' <<< "$R08_ORIGINAL_BLOCK"; then
  pass
else
  fail 'R08 original language must come from exact-UID local SQLite profile'
fi
if grep -Fq 'qa_firestore_read_driver' <<< "$R08_UPDATED_BLOCK" \
  && grep -Fq -- '--profile r08-preferences-baseline' <<< "$R08_UPDATED_BLOCK" \
  && ! grep -Fq 'QA_R08_ORIGINAL_LANGUAGE=' <<< "$R08_UPDATED_BLOCK"; then
  pass
else
  fail 'R08 cloud updatedAt baseline must not replace the local original language'
fi

MOUNT_OWNERSHIP_BLOCK="$(sed -n \
  '/^acquire_qa_app_mount_cleanup_ownership() {/,/^}/p' \
  "$SIM_REVIEW")"
if grep -Fq 'bind_qa_session_uid_from_auth_export || return 1' \
    <<< "$MOUNT_OWNERSHIP_BLOCK" \
  && grep -Fq 'FIXTURE_CLEANUP_REQUIRED=1' <<< "$MOUNT_OWNERSHIP_BLOCK" \
  && grep -Fq 'READY_IDENTITY_HASH' <<< "$MOUNT_OWNERSHIP_BLOCK"; then
  pass
else
  fail 'every QaApp mount must exact-bind UID and acquire cleanup ownership'
fi

OPERATION_LAUNCH_BLOCK="$(sed -n \
  '/^run_and_validate_qa_operation() {/,/^}/p' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh")"
OPEN_APP_LAUNCH_BLOCK="$(sed -n \
  '/^run_and_validate_qa_open_app_operation() {/,/^}/p' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh")"
for launch_name in operation open-app; do
  if [ "$launch_name" = operation ]; then
    launch_block="$OPERATION_LAUNCH_BLOCK"
  else
    launch_block="$OPEN_APP_LAUNCH_BLOCK"
  fi
  ownership_line="$(grep -n -m1 'acquire_qa_app_mount_cleanup_ownership' \
    <<< "$launch_block" | cut -d: -f1)"
  launch_line="$(grep -n -m1 'qa_launch_app_with_marker_stream' \
    <<< "$launch_block" | cut -d: -f1)"
  if [ -n "$ownership_line" ] \
    && [ -n "$launch_line" ] \
    && [ "$ownership_line" -lt "$launch_line" ]; then
    pass
  else
    fail "$launch_name must acquire cleanup ownership before QaApp launch"
  fi
done

CLEANUP_BLOCK="$(sed -n '/^cleanup_sim_review() {/,/^}/p' "$SIM_REVIEW")"
cleanup_line="$(grep -n -m1 'cleanup_qa_fixtures_if_required' \
  <<< "$CLEANUP_BLOCK" | cut -d: -f1)"
dispose_line="$(grep -n -m1 'dispose_qa_identity_if_required' \
  <<< "$CLEANUP_BLOCK" | cut -d: -f1)"
if [ -n "$cleanup_line" ] \
  && [ -n "$dispose_line" ] \
  && [ "$cleanup_line" -lt "$dispose_line" ] \
  && grep -Fq 'cleanup_status=1' <<< "$CLEANUP_BLOCK"; then
  pass
else
  fail 'cleanup failure must be aggregated before independent Auth disposal'
fi

require_literal 'trusted verifier bootstrap must be explicitly staged' \
  "$SIM_REVIEW" '## Trusted verifier staged bootstrap'
require_literal 'missing trusted main verifier must remain fail closed' \
  "$SIM_REVIEW" 'trusted main 尚未包含 verifier 時停止 session。'
require_literal 'candidate verifier must never bootstrap its own trust' \
  "$SIM_REVIEW" 'candidate verifier 不得驗證或物化自身。'

"$PYTHON_BIN" -I - "$SNAPSHOT_PROBE" <<'PY'
import importlib.util
import os
import pathlib
import stat
import subprocess
import sys
import tempfile


probe_path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("qa_repo_snapshot", probe_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary_root:
    root = pathlib.Path(temporary_root).resolve() / "tree"
    root.mkdir()
    file_path = root / "data.txt"
    file_path.write_text("safe\n", encoding="utf-8")
    baseline = module.tree_manifest(root)

    empty = root / "empty"
    empty.mkdir()
    assert module.tree_manifest(root) != baseline
    empty.rmdir()

    original_mode = stat.S_IMODE(file_path.stat().st_mode)
    file_path.chmod(0o700)
    assert module.tree_manifest(root) != baseline
    file_path.chmod(original_mode)

    symlink = root / "link"
    symlink.symlink_to(file_path)
    try:
        module.tree_manifest(root)
    except module.SnapshotFailure:
        pass
    else:
        raise AssertionError("symlink mutation accepted")
    symlink.unlink()

    fifo = root / "fifo"
    os.mkfifo(fifo)
    try:
        module.tree_manifest(root)
    except module.SnapshotFailure:
        pass
    else:
        raise AssertionError("FIFO mutation accepted")
    fifo.unlink()

    hardlink = root / "hardlink"
    os.link(file_path, hardlink)
    try:
        module.tree_manifest(root)
    except module.SnapshotFailure:
        pass
    else:
        raise AssertionError("hardlink mutation accepted")
    hardlink.unlink()

with tempfile.TemporaryDirectory() as temporary_root:
    repository = pathlib.Path(temporary_root).resolve() / "repository"
    repository.mkdir()
    subprocess.run(["git", "-C", repository, "init", "-q"], check=True)
    tracked = repository / "tracked.txt"
    tracked.write_text("tracked\n", encoding="utf-8")
    subprocess.run(["git", "-C", repository, "add", "tracked.txt"], check=True)
    subprocess.run(
        [
            "git", "-C", repository,
            "-c", "user.name=QA Test",
            "-c", "user.email=qa-test@example.invalid",
            "commit", "-qm", "base",
        ],
        check=True,
    )
    untracked = repository / "untracked.sh"
    untracked.write_text("exit 0\n", encoding="utf-8")
    before_mode = module.snapshot_payload(repository, "fixture", "quality-snapshot/v1")
    untracked.chmod(0o700)
    after_mode = module.snapshot_payload(repository, "fixture", "quality-snapshot/v1")
    assert before_mode != after_mode
    hardlink = repository / "untracked-hardlink.sh"
    os.link(untracked, hardlink)
    try:
        module.snapshot_payload(repository, "fixture", "quality-snapshot/v1")
    except module.SnapshotFailure:
        pass
    else:
        raise AssertionError("source hardlink accepted")
    hardlink.unlink()
    untracked.unlink()
    tracked.unlink()
    deleted_snapshot = module.snapshot_payload(
        repository,
        "fixture",
        "quality-snapshot/v1",
    )
    assert deleted_snapshot != before_mode
PY
if [ "$?" -eq 0 ]; then
  pass
else
  fail 'trusted topology mutation tests failed'
fi

printf '=== Results: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
