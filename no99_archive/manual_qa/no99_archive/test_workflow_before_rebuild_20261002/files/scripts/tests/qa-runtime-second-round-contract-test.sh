#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GAME_TEST="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$CONTROL_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" --role test-run > "$GAME_TEST"
SIM_REVIEW="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$CONTROL_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" > "$SIM_REVIEW"
AUTH_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py"
FIRESTORE_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firestore-read.py"
QUALITY_GOLDEN_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-quality-golden.py"
APP_DELEGATE_GUARD="$CONTROL_ROOT/scripts/qa-app-delegate-guard.py"
FIXTURE_WRITE_POLICY="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-fixture-write-policy.sh"
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

TEST_ROOT="$(mktemp -d)"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/firebase" <<'FIREBASE_STUB'
#!/bin/sh
set -eu
: "${FIREBASE_STUB_TRACE:?}"
: "${FIREBASE_STUB_MODE:?}"
printf '%s\n' "$*" >> "$FIREBASE_STUB_TRACE"
case " $* " in
  *" --project susugigi-qa "*) ;;
  *) exit 64 ;;
esac
case " $* " in
  *" --non-interactive "*) ;;
  *) exit 65 ;;
esac
case " $* " in
  *" auth:export "*) ;;
  *) exit 66 ;;
esac
export_path=""
for argument in "$@"; do
  case "$argument" in
    *.json) export_path="$argument" ;;
  esac
done
[ -n "$export_path" ] || exit 67
case "$FIREBASE_STUB_MODE" in
  absent)
    printf '%s\n' '{"users":[{"localId":"differentQaUser"}]}' > "$export_path"
    ;;
  present)
    printf '%s\n' '{"users":[{"localId":"rawQaUser1234567890"}]}' > "$export_path"
    ;;
  multi)
    printf '%s\n' '{"users":[{"localId":"rawQaUser1234567890"},{"localId":"rawQaUser1234567890"}]}' > "$export_path"
    ;;
  *) exit 68 ;;
esac
FIREBASE_STUB
chmod 700 "$TEST_ROOT/bin/firebase"

RAW_UID='rawQaUser1234567890'
RAW_UID_HASH="$(printf '%s' "$RAW_UID" | shasum -a 256 | awk '{print $1}')"
: > "$TEST_ROOT/firebase-trace"
if printf '%s\n' "$RAW_UID_HASH" \
  | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    FIREBASE_STUB_TRACE="$TEST_ROOT/firebase-trace" \
    FIREBASE_STUB_MODE=absent \
    "$PYTHON_BIN" "$AUTH_PROBE" --project susugigi-qa \
      > "$TEST_ROOT/auth-absent.out" 2> "$TEST_ROOT/auth-absent.err" \
  && grep -Fxq QA_AUTH_IDENTITY_ABSENT "$TEST_ROOT/auth-absent.out" \
  && [ ! -s "$TEST_ROOT/auth-absent.err" ] \
  && ! grep -Fq "$RAW_UID" "$TEST_ROOT/auth-absent.out" "$TEST_ROOT/auth-absent.err"; then
  pass
else
  fail 'Auth absence probe must use the QA-bound non-interactive Firebase export seam without leaking UID'
fi

: > "$TEST_ROOT/firebase-trace"
if printf '%s\n' "$RAW_UID_HASH" \
  | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    FIREBASE_STUB_TRACE="$TEST_ROOT/firebase-trace" \
    FIREBASE_STUB_MODE=present \
    "$PYTHON_BIN" "$AUTH_PROBE" --project susugigi-qa \
      > "$TEST_ROOT/auth-present.out" 2> "$TEST_ROOT/auth-present.err"; then
  fail 'Auth absence probe must fail when the exact identity remains'
elif grep -Fxq QA_AUTH_IDENTITY_PRESENT "$TEST_ROOT/auth-present.err" \
  && [ ! -s "$TEST_ROOT/auth-present.out" ] \
  && ! grep -Fq "$RAW_UID" "$TEST_ROOT/auth-present.out" "$TEST_ROOT/auth-present.err"; then
  pass
else
  fail 'Auth presence verdict must be fixed and must not reveal UID'
fi

: > "$TEST_ROOT/firebase-trace"
if printf '%s\n' "$RAW_UID_HASH" \
  | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    FIREBASE_STUB_TRACE="$TEST_ROOT/firebase-trace" \
    FIREBASE_STUB_MODE=absent \
    "$PYTHON_BIN" "$AUTH_PROBE" --project susugigi-production \
      > "$TEST_ROOT/auth-production.out" 2> "$TEST_ROOT/auth-production.err"; then
  fail 'Auth absence probe must reject Production before invoking Firebase CLI'
elif [ ! -s "$TEST_ROOT/firebase-trace" ] \
  && ! grep -Fq "$RAW_UID" "$TEST_ROOT/auth-production.out" "$TEST_ROOT/auth-production.err"; then
  pass
else
  fail 'Production rejection must not invoke Firebase CLI or leak UID'
fi

for bind_mode in absent multi; do
  if printf '%s\n' "$RAW_UID_HASH" \
    | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
      FIREBASE_STUB_TRACE="$TEST_ROOT/firebase-trace" \
      FIREBASE_STUB_MODE="$bind_mode" \
      "$PYTHON_BIN" "$AUTH_PROBE" --project susugigi-qa --resolve-exact-uid \
        > "$TEST_ROOT/auth-bind-$bind_mode.out" \
        2> "$TEST_ROOT/auth-bind-$bind_mode.err"; then
    fail "Auth UID binding must reject $bind_mode matches"
  elif [ ! -s "$TEST_ROOT/auth-bind-$bind_mode.out" ] \
    && grep -Fxq QA_AUTH_IDENTITY_BIND_FAILED "$TEST_ROOT/auth-bind-$bind_mode.err" \
    && ! grep -Fq "$RAW_UID" "$TEST_ROOT/auth-bind-$bind_mode.err"; then
    pass
  else
    fail "Auth UID binding $bind_mode failure must be fixed and private"
  fi
done

if printf '%s\n' "$RAW_UID_HASH" \
  | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    FIREBASE_STUB_TRACE="$TEST_ROOT/firebase-trace" \
    FIREBASE_STUB_MODE=present \
    "$PYTHON_BIN" "$AUTH_PROBE" --project susugigi-qa --resolve-exact-uid \
      > "$TEST_ROOT/auth-bind-exact.out" 2> "$TEST_ROOT/auth-bind-exact.err" \
  && grep -Fxq "$RAW_UID" "$TEST_ROOT/auth-bind-exact.out" \
  && [ ! -s "$TEST_ROOT/auth-bind-exact.err" ]; then
  pass
else
  fail 'Auth UID binding must return only the exact anonymous UID to command substitution'
fi

if printf '%s\n' 'session-user' \
  | PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    FIREBASE_STUB_TRACE="$TEST_ROOT/firebase-trace" \
    FIREBASE_STUB_MODE=absent \
    "$PYTHON_BIN" "$FIRESTORE_PROBE" \
      --project susugigi-qa \
      --profile r01-user-anonymous \
      > "$TEST_ROOT/firestore.out" 2> "$TEST_ROOT/firestore.err"; then
  fail 'Firestore read must fail closed when no supported OAuth provider exists'
elif [ ! -s "$TEST_ROOT/firestore.out" ] \
  && grep -Fxq QA_FIRESTORE_AUTH_PROVIDER_UNAVAILABLE "$TEST_ROOT/firestore.err" \
  && ! grep -Fq 'session-user' "$TEST_ROOT/firestore.out" "$TEST_ROOT/firestore.err"; then
  pass
else
  fail 'Firestore dependency failure must use a fixed allowlisted verdict'
fi

require_literal 'game-test must state the Firestore credential dependency contract' \
  "$GAME_TEST" 'Firestore document read 只接受受支援的 OAuth provider。'
require_literal 'sim-review must state the Firestore credential dependency contract' \
  "$SIM_REVIEW" 'Firestore document read 只接受受支援的 OAuth provider。'

for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  reject_literal 'txnIndex capture runtime must be removed for permanently blocked scenes' \
    "$skill" 'capture_qa_original_transaction_id_from_session_entitlement'
  reject_literal 'txnIndex read runtime must be removed for permanently blocked scenes' \
    "$skill" 'run_qa_txn_index_exact_doc_probe'
  reject_literal 'txnIndex resource path must never be executable' \
    "$skill" 'txnIndex/$QA_ORIGINAL_TRANSACTION_ID'
done

require_literal 'game-test quality identity must carry repository' \
  "$GAME_TEST" '- `repository`'
require_literal 'sim-review must source the quality repository from the locked identity' \
  "$SIM_REVIEW" 'QUALITY_REPOSITORY="$QUALITY_IDENTITY_REPOSITORY"'
require_literal 'sim-review must reject an empty quality repository' \
  "$SIM_REVIEW" 'test -n "$QUALITY_REPOSITORY"'

for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  require_literal 'payload must carry a trusted Control Plane root' \
    "$skill" '`trustedControlPlaneRoot`'
done
require_literal 'trusted verifier root must differ from candidate root' \
  "$SIM_REVIEW" '[ "$TRUSTED_CONTROL_PLANE_ROOT" != "$CONTROL_PLANE_ROOT" ]'
require_literal 'candidate snapshot must be calculated by the trusted verifier' \
  "$SIM_REVIEW" 'python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER"'
require_literal 'trusted verifier must be materialized from the locked Git blob' \
  "$SIM_REVIEW" 'git -C "$TRUSTED_CONTROL_PLANE_ROOT" show "$TRUSTED_CONTROL_PLANE_COMMIT:scripts/qa-repo-snapshot.py"'
reject_literal 'candidate verifier must never validate its own candidate snapshot' \
  "$SIM_REVIEW" 'python3 "$CONTROL_PLANE_ROOT/scripts/qa-repo-snapshot.py"'

mkdir -p "$TEST_ROOT/candidate/scripts"
git -C "$TEST_ROOT" init -q candidate
git -C "$TEST_ROOT/candidate" config user.name 'Candidate Test'
git -C "$TEST_ROOT/candidate" config user.email 'candidate@example.invalid'
printf '%s\n' safe > "$TEST_ROOT/candidate/tracked.txt"
git -C "$TEST_ROOT/candidate" add tracked.txt
git -C "$TEST_ROOT/candidate" commit -qm base
cat > "$TEST_ROOT/candidate/scripts/qa-repo-snapshot.py" <<'MALICIOUS_VERIFIER'
#!/usr/bin/env python3
print('forged-snapshot')
MALICIOUS_VERIFIER
CANDIDATE_SNAPSHOT="$($PYTHON_BIN "$TEST_ROOT/candidate/scripts/qa-repo-snapshot.py")"
TRUSTED_SNAPSHOT="$($PYTHON_BIN "$CONTROL_ROOT/scripts/qa-repo-snapshot.py" \
  --repo "$TEST_ROOT/candidate" \
  --repository 'github:test/candidate' \
  --schema control-plane-snapshot/v1)"
if [ "$CANDIDATE_SNAPSHOT" = forged-snapshot ] \
  && [[ "$TRUSTED_SNAPSHOT" =~ ^[0-9a-f]{64}$ ]] \
  && [ "$TRUSTED_SNAPSHOT" != "$CANDIDATE_SNAPSHOT" ]; then
  pass
else
  fail 'A malicious verifier inside the candidate Control root must not bypass snapshot verification'
fi

mkdir -p "$TEST_ROOT/app-delegate"
cat > "$TEST_ROOT/app-delegate/production-only.swift" <<'SWIFT'
#if !QA
@_implementationOnly import GoogleSignIn
func route(_ url: URL) -> Bool {
  GIDSignIn . sharedInstance.handle ( url )
}
#endif
SWIFT
if python3 "$APP_DELEGATE_GUARD" "$TEST_ROOT/app-delegate/production-only.swift" \
  > "$TEST_ROOT/app-production.out" 2> "$TEST_ROOT/app-production.err"; then
  pass
else
  fail 'Production-only GoogleSignIn variants must remain allowed'
fi

cat > "$TEST_ROOT/app-delegate/qa-import.swift" <<'SWIFT'
#if QA
@_implementationOnly import GoogleSignIn
#endif
SWIFT
if python3 "$APP_DELEGATE_GUARD" "$TEST_ROOT/app-delegate/qa-import.swift" \
  > "$TEST_ROOT/app-import.out" 2> "$TEST_ROOT/app-import.err"; then
  fail 'QA-active implementation-only GoogleSignIn import must be rejected'
else
  pass
fi

cat > "$TEST_ROOT/app-delegate/qa-reference.swift" <<'SWIFT'
#if QA
let qaSignIn = GIDSignIn . sharedInstance
#else
let productionOnly = true
#endif
SWIFT
if python3 "$APP_DELEGATE_GUARD" "$TEST_ROOT/app-delegate/qa-reference.swift" \
  > "$TEST_ROOT/app-reference.out" 2> "$TEST_ROOT/app-reference.err"; then
  fail 'Every QA-active GIDSignIn reference variant must be rejected'
else
  pass
fi

require_literal 'remote fixture write must have a UID binding gate' \
  "$SIM_REVIEW" 'require_qa_fixture_cleanup_binding_before_write() {'
require_literal 'fixture write policy must be derived by checked-in runtime helper' \
  "$SIM_REVIEW" 'derive_qa_fixture_write_policy() {'
require_literal 'runner must execute the checked-in fixture policy helper' \
  "$SIM_REVIEW" 'bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-fixture-write-policy.sh"'
require_literal 'runner must promote remote-write policy to active cleanup gate' \
  "$SIM_REVIEW" 'QA_REMOTE_FIXTURE_WRITE_POSSIBLE=1'
require_literal 'runner must promote reseed policy to active cleanup gate' \
  "$SIM_REVIEW" 'QA_FIXTURE_RESEED_REQUIRED=1'
require_literal 'policy derivation must run before R13 binding and prepare cleanup' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" 'derive_qa_fixture_write_policy || return 1'
if [ -f "$FIXTURE_WRITE_POLICY" ]; then
  pass
else
  fail 'checked-in fixture write policy helper must exist'
fi
require_literal 'every remote-writing prepare must require pre-seed cleanup' \
  "$SIM_REVIEW" '所有可能遠端寫入的 fixture prepare 都必須在 launch 前清除同 UID 的既有 subtree。'
require_literal 'generic pre-seed cleanup must derive from remote-write capability' \
  "$SIM_REVIEW" '[ "$QA_REMOTE_FIXTURE_WRITE_POSSIBLE" != 1 ] \
    && [ "$QA_FIXTURE_RESEED_REQUIRED" != 1 ]'
reject_literal 'pre-seed cleanup must not be limited to r02_end' \
  "$SIM_REVIEW" '[ "$PREPARE_SCENE" = r02_end ]'
FIXTURE_BIND_CALLS="$(grep -Fh 'require_qa_fixture_cleanup_binding_before_write' \
  "$SIM_REVIEW" "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" | wc -l | tr -d ' ')"
if [ "$FIXTURE_BIND_CALLS" -ge 3 ]; then
  pass
else
  fail 'prepare and open-app remote-write paths must call the UID binding gate'
fi
reject_literal 'fixture cleanup failure must not skip Auth disposal' \
  "$SIM_REVIEW" 'elif ! dispose_qa_identity_if_required; then'
require_literal 'cleanup failure must still attempt Auth disposal' \
  "$SIM_REVIEW" 'fixture cleanup 失敗時仍必須嘗試匿名帳號 disposal。'
require_literal 'cleanup must independently prove the fixture subtree absent' \
  "$SIM_REVIEW" 'verify_qa_fixture_cleanup_absence() {'
require_literal 'R03 initial profile must be explicitly mapped' \
  "$SIM_REVIEW" 'R03:CS-02) QA_FIRESTORE_PROFILE=r03-initial-backup; qa_quality_profile_key=r03_initial_backup; qa_expected_checkpoint_key=R03:9'
require_literal 'R03 incremental profile must be explicitly mapped' \
  "$SIM_REVIEW" 'R03:CS-03) QA_FIRESTORE_PROFILE=r03-incremental-backup; qa_quality_profile_key=r03_incremental_backup; qa_expected_checkpoint_key=R03:21'
require_literal 'R01 anonymous profile must be explicitly mapped' \
  "$SIM_REVIEW" 'R01:AU-01) QA_FIRESTORE_PROFILE=r01-user-anonymous; qa_quality_profile_key=r01_anonymous_user; qa_expected_checkpoint_key=R01:11'
require_literal 'R01 unchanged profile must be explicitly mapped' \
  "$SIM_REVIEW" 'R01:AU-03) QA_FIRESTORE_PROFILE=r01-user-unchanged; qa_quality_profile_key=r01_user_unchanged; qa_expected_checkpoint_key=R01:15'
require_literal 'R08 preferences profile must be explicitly mapped' \
  "$SIM_REVIEW" 'R08:CS-01) QA_FIRESTORE_PROFILE=r08-preferences; qa_quality_profile_key=r08_preferences; qa_expected_checkpoint_key=R08:21'
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  require_literal 'payload must lock the executable Firestore checkpoint map' \
    "$skill" '`firestoreCheckpointMap`'
  require_literal 'payload must lock the executable SQLite checkpoint map' \
    "$skill" '`sqliteCheckpointMap`'
done
require_literal 'R13 SQLite profile must use the locked Quality checkpoint' \
  "$SIM_REVIEW" '`R13:RC-06` 對 `R13:6` 與 `r13_schedule_backfill`'
require_literal 'R13 must establish an exact Auth binding before cleanup and prepare' \
  "$SIM_REVIEW" 'prepare_r13_fixture_cleanup_binding_if_required() {'
require_literal 'R13 pre-seed binding must use Auth export without resuming sync' \
  "$SIM_REVIEW" 'bind_qa_session_uid_from_auth_export || return 1'
require_literal 'R13 SQLite binding must happen only as a post-prepare cross-check' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" 'verify_r13_prepared_sqlite_identity || return 1'
require_literal 'sim-review must derive the locked Quality golden path' \
  "$SIM_REVIEW" 'QUALITY_FIXTURE_GOLDEN="$SESSION_QUALITY_ROOT/no3_run_scripts/no1_fixture_golden.json"'
require_literal 'sim-review must validate selected Quality profile with checked-in evaluator' \
  "$SIM_REVIEW" 'python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py"'
require_literal 'sim-review must require the fixed golden evaluator verdict' \
  "$SIM_REVIEW" '[ "$qa_quality_golden_output" = QA_QUALITY_FIRESTORE_PROFILE_MATCH ]'
require_literal 'candidate prepare fingerprint must be evaluated against locked Quality golden' \
  "$SIM_REVIEW" 'require_locked_quality_scene_prepare() {'
require_literal 'prepare evaluator must use the checked-in helper' \
  "$SIM_REVIEW" '--scene-prepare "$qa_scene_id"'
require_literal 'candidate inspect facts must be evaluated against locked Quality golden' \
  "$SIM_REVIEW" 'require_locked_quality_scene_result() {'
require_literal 'facts evaluator must use the checked-in helper' \
  "$SIM_REVIEW" '--scene-result "$qa_scene_id"'
require_literal 'candidate pass verdict alone must not satisfy inspect' \
  "$SIM_REVIEW" '候選 App 的 `verdict=pass` 不足以通過 inspect。'
require_literal 'operation validator must invoke the independent prepare evaluator' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" 'require_locked_quality_scene_prepare "$PREPARE_SCENE" "$qa_result"'
require_literal 'operation validator must invoke the independent facts evaluator' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" 'require_locked_quality_scene_result "$QA_PREPARE_SCENE" "$qa_result"'
require_literal 'R13 inspect facts must use the locked SQLite profile evaluator' \
  "$SIM_REVIEW" 'query_locked_quality_r13_sqlite_profile() {'
require_literal 'R13 evaluator must execute the checked-in SQLite mode' \
  "$SIM_REVIEW" '--r13-sqlite-result r13_schedule_backfill'
require_literal 'R13 operation validator must invoke the independent SQLite evaluator' \
  "$SIM_REVIEW" 'query_locked_quality_r13_sqlite_profile || exit 1'
require_literal 'R13 candidate result must be evaluated independently' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" 'evaluate_locked_quality_r13_candidate_result "$qa_result"'
require_literal 'R13 candidate SQLite and marker results must agree' \
  "$SIM_REVIEW" 'require_r13_candidate_sqlite_marker_three_way || exit 1'
if [ -x "$QUALITY_GOLDEN_PROBE" ] || [ -f "$QUALITY_GOLDEN_PROBE" ]; then
  pass
else
  fail 'checked-in Quality golden evaluator must exist'
fi
require_literal 'blocked Firestore scenes must remain unexecutable' \
  "$SIM_REVIEW" "R10:*|R11:*|R12:*) printf '%s\\n' QA_BLOCKED_FIRESTORE_PROFILE_REJECTED"
require_literal 'R03 initial backup must require remote absence and initial mode markers' \
  "$SIM_REVIEW" 'require_r03_initial_backup_markers() {'
require_literal 'R03 initial backup must reject device cooldown skip' \
  "$SIM_REVIEW" "grep -Eq '^QA BACKUP skip reason=cooldown([[:space:]]|$)'"
reject_literal 'R08 must not capture original language at CS-01 start' \
  "$SIM_REVIEW" 'capture_r08_preferences_baseline() {'
require_literal 'R08 original language must have a scene-level private capture' \
  "$SIM_REVIEW" 'capture_r08_original_language_before_manual_changes() {'
require_literal 'R08 CS-01 must have an independent updatedAt capture' \
  "$SIM_REVIEW" 'capture_r08_cs01_updated_at_baseline() {'
require_literal 'R08 original language must be stored separately' \
  "$SIM_REVIEW" 'QA_R08_ORIGINAL_LANGUAGE='
require_literal 'R08 CS-01 timestamp must be stored separately' \
  "$SIM_REVIEW" 'QA_R08_CS01_BASELINE_UPDATED_AT='
require_literal 'R08 scene setup must capture language before manual cases' \
  "$SIM_REVIEW" 'capture_r08_original_language_before_manual_changes || exit 1'
require_literal 'R08 CS-01 setup must capture only its updatedAt baseline' \
  "$SIM_REVIEW" 'capture_r08_cs01_updated_at_baseline || exit 1'
require_literal 'simulator cold reopen must be runner-owned' \
  "$SIM_REVIEW" 'run_qa_manual_cold_reopen() {'
require_literal 'runner-owned cold reopen must cover R01 R02 and R08' \
  "$SIM_REVIEW" 'R01:cold-reopen|R02:cold-reopen|R08:cold-reopen)'

printf '=== Results: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
