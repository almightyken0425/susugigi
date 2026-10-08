#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIM_REVIEW="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$CONTROL_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" > "$SIM_REVIEW"
GAME_TEST="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$CONTROL_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" --role test-run > "$GAME_TEST"
AUTH_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py"
FIRESTORE_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firestore-read.py"
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

for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  require_literal 'runtime contract must require private immutable snapshots' \
    "$skill" 'session-owned immutable private snapshot'
done
require_literal 'runner must create a private Control runtime snapshot' \
  "$SIM_REVIEW" 'SESSION_CONTROL_PLANE_ROOT='
require_literal 'runner must create a private Quality runtime snapshot' \
  "$SIM_REVIEW" 'SESSION_QUALITY_ROOT='
require_literal 'trusted verifier must be copied from its locked Git object' \
  "$SIM_REVIEW" 'git -C "$TRUSTED_CONTROL_PLANE_ROOT" show "$TRUSTED_CONTROL_PLANE_COMMIT:scripts/qa-repo-snapshot.py"'
require_literal 'runner must make the session snapshots read-only' \
  "$SIM_REVIEW" 'chmod -R a-w "$SESSION_RUNTIME_ROOT"'
require_literal 'every session helper must have a pre and post manifest check' \
  "$SIM_REVIEW" 'run_session_snapshot_command() {'
require_literal 'session command wrapper must discard results after post-check failure' \
  "$SIM_REVIEW" 'require_session_runtime_snapshots_current || return 1'
require_literal 'private snapshots must reject hardlinked files' \
  "$SIM_REVIEW" '-type f -links +1 -print -quit'
require_literal 'fixture policy must execute from the private Control snapshot' \
  "$SIM_REVIEW" 'bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-fixture-write-policy.sh"'
require_literal 'fixture cleanup must execute from the private Quality snapshot' \
  "$SIM_REVIEW" '"$SESSION_QUALITY_ROOT/no2_qa_tools/cleanup_qa_fixtures.sh"'
require_literal 'golden must be read from the private Quality snapshot' \
  "$SIM_REVIEW" 'QUALITY_FIXTURE_GOLDEN="$SESSION_QUALITY_ROOT/no3_run_scripts/no1_fixture_golden.json"'
reject_literal 'runtime helpers must not execute from mutable candidate Control root' \
  "$SIM_REVIEW" 'python3 "$CONTROL_PLANE_ROOT/scripts/'
reject_literal 'runtime Quality executable must not execute from mutable candidate Quality root' \
  "$SIM_REVIEW" 'bash "$QUALITY_ROOT/no2_qa_tools/'

for endpoint_name in \
  FIREBASE_GOOGLE_URL \
  FIREBASE_TOKEN_URL \
  FIREBASE_AUTH_URL \
  FIREBASE_AUTHPROXY_URL \
  FIREBASE_AUTH_MANAGEMENT_URL \
  FIREBASE_IDENTITY_URL \
  FIREBASE_API_URL \
  FIREBASE_AUTH_EMULATOR_HOST \
  FIRESTORE_EMULATOR_HOST \
  FIRESTORE_URL \
  FIREBASE_EMULATOR_HUB \
  CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
  CLOUDSDK_AUTH_TOKEN_HOST; do
  require_literal "Auth probe must inventory $endpoint_name" "$AUTH_PROBE" "$endpoint_name"
  require_literal "Firestore probe must inventory $endpoint_name" "$FIRESTORE_PROBE" "$endpoint_name"
done

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/firebase" <<'FIREBASE_STUB'
#!/usr/bin/env bash
printf x > "$QA_CHILD_WAS_RUN"
exit 99
FIREBASE_STUB
cat > "$TEST_ROOT/bin/gcloud" <<'GCLOUD_STUB'
#!/usr/bin/env bash
printf x > "$QA_CHILD_WAS_RUN"
exit 99
GCLOUD_STUB
chmod 700 "$TEST_ROOT/bin/firebase" "$TEST_ROOT/bin/gcloud"

for probe_kind in auth firestore; do
  : > "$TEST_ROOT/child-$probe_kind"
  case "$probe_kind" in
    auth)
      if printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
        | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
          QA_CHILD_WAS_RUN="$TEST_ROOT/child-$probe_kind" \
          FIREBASE_GOOGLE_URL='https://attacker.invalid' \
          "$PYTHON_BIN" "$AUTH_PROBE" --project susugigi-qa \
          > "$TEST_ROOT/$probe_kind.out" 2> "$TEST_ROOT/$probe_kind.err"; then
        fail 'Auth probe must reject endpoint override'
      elif [ ! -s "$TEST_ROOT/child-$probe_kind" ] \
        && grep -Fxq QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED "$TEST_ROOT/$probe_kind.err"; then
        pass
      else
        fail 'Auth endpoint override must be rejected before child execution'
      fi
      ;;
    firestore)
      if printf '%s\n' 'qaSessionUid' \
        | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
          QA_CHILD_WAS_RUN="$TEST_ROOT/child-$probe_kind" \
          CLOUDSDK_AUTH_TOKEN_HOST='https://attacker.invalid' \
          "$PYTHON_BIN" "$FIRESTORE_PROBE" \
            --project susugigi-qa \
            --profile r01-user-anonymous \
          > "$TEST_ROOT/$probe_kind.out" 2> "$TEST_ROOT/$probe_kind.err"; then
        fail 'Firestore probe must reject endpoint override'
      elif [ ! -s "$TEST_ROOT/child-$probe_kind" ] \
        && grep -Fxq QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED "$TEST_ROOT/$probe_kind.err"; then
        pass
      else
        fail 'Firestore endpoint override must be rejected before child execution'
      fi
      ;;
  esac
done

require_literal 'R13 runner must call the locked Quality aggregate helper' \
  "$SIM_REVIEW" 'query_locked_quality_r13_sqlite_profile() {'
require_literal 'R13 aggregate helper must receive UID only on stdin' \
  "$SIM_REVIEW" '| run_session_snapshot_command \
          bash "$SESSION_QUALITY_ROOT/no2_qa_tools/query_local_db.sh" \
      --bundle-id "$QA_BUNDLE_ID" \
      --session-uid-stdin \
      profile r13_schedule_backfill'
require_literal 'R13 candidate result must be evaluated separately' \
  "$SIM_REVIEW" '--r13-candidate-result r13_schedule_backfill'
require_literal 'R13 SQLite aggregate must be evaluated separately' \
  "$SIM_REVIEW" '--r13-sqlite-result r13_schedule_backfill'
require_literal 'R13 three-way comparison must include the SCHED marker' \
  "$SIM_REVIEW" 'require_r13_candidate_sqlite_marker_three_way() {'
reject_literal 'candidate inspect JSON must not be treated as SQLite output' \
  "$SIM_REVIEW" '--sqlite-result r13_schedule_backfill'

require_literal 'R08 language capture must establish exact UID binding first' \
  "$SIM_REVIEW" 'bind_r08_identity_before_language_capture() {'
require_literal 'R08 binding must use exact Auth export matching' \
  "$SIM_REVIEW" 'bind_qa_session_uid_from_auth_export || return 1'
require_literal 'R08 binding must precede original-language capture' \
  "$SIM_REVIEW" 'bind_r08_identity_before_language_capture || exit 1'

require_literal 'R01 must keep independent login baseline' \
  "$SIM_REVIEW" 'QA_R01_LAST_LOGIN_AT_BASELINE='
require_literal 'R01 must keep independent updatedAt baseline' \
  "$SIM_REVIEW" 'QA_R01_UPDATED_AT_BASELINE='
require_literal 'R01 unchanged probe must receive login baseline' \
  "$SIM_REVIEW" '--minimum-last-login-at "$QA_R01_LAST_LOGIN_AT_BASELINE"'
require_literal 'R01 unchanged probe must receive updatedAt baseline' \
  "$SIM_REVIEW" '--minimum-updated-at "$QA_R01_UPDATED_AT_BASELINE"'

printf '=== Results: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
