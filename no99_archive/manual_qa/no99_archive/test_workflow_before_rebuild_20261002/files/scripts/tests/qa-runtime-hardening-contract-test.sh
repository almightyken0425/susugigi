#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GAME_TEST="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$TEST_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" --role test-run > "$GAME_TEST"
SIM_REVIEW="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$TEST_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" > "$SIM_REVIEW"
MARKER_FILTER="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py"
FIRESTORE_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firestore-read.py"
AUTH_PROBE="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py"
APP_DELEGATE_GUARD="$TEST_ROOT/scripts/qa-app-delegate-guard.py"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
}

require_literal() {
  local name="$1"
  local file="$2"
  local literal="$3"

  if grep -Fq -- "$literal" "$file"; then
    pass
  else
    fail "$name"
  fi
}

forbid_literal() {
  local name="$1"
  local file="$2"
  local literal="$3"

  if grep -Fq -- "$literal" "$file"; then
    fail "$name"
  else
    pass
  fi
}

echo '=== Candidate roots ==='
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  require_literal 'payload 缺 controlPlaneWorktreeOrRepo' "$skill" '`controlPlaneWorktreeOrRepo`'
  require_literal 'payload 缺 qualityWorktreeOrRepo' "$skill" '`qualityWorktreeOrRepo`'
  require_literal 'Control runtime 未使用 immutable snapshot' "$skill" 'session-owned immutable private snapshot'
  require_literal 'helper 未做 private manifest 前後驗' "$skill" 'helper 前後重算私有 tree manifest'
  forbid_literal '不得固定使用 installed main helper' "$skill" '$HOME/.codex/scripts/qa-'
done
require_literal 'candidate resolver 未綁 session Control root' "$SIM_REVIEW" '"$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-project.sh"'
require_literal 'candidate marker filter 未綁 session Control root' "$SIM_REVIEW" '"$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py"'
SESSION_COMMAND_GUARD_COUNT="$(grep -Fc 'run_session_snapshot_command' "$SIM_REVIEW" || true)"
SOURCE_IDENTITY_GUARD_COUNT="$(grep -Fc 'require_control_plane_identity_current' "$SIM_REVIEW" || true)"
if [ "$SESSION_COMMAND_GUARD_COUNT" -ge 16 ]; then
  pass
else
  fail '每次 session helper 前後都必須重算 private manifest'
fi
if [ "$SOURCE_IDENTITY_GUARD_COUNT" -ge 4 ]; then
  pass
else
  fail 'source pre 與 post 都必須重算 identity'
fi

echo '=== Session token transport ==='
forbid_literal 'session token 不得進 App argv' "$SIM_REVIEW" '--qa-session-token "$QA_SESSION_TOKEN"'
APP_CONSOLE_LAUNCH_COUNT="$(grep -Fh 'qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN"' \
  "$SIM_REVIEW" "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" | wc -l | tr -d ' ')"
if [ "$APP_CONSOLE_LAUNCH_COUNT" -ge 4 ] \
  && grep -Fq 'SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN="$qa_session_token"' \
    "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh"; then
  pass
else
  fail 'bootstrap operation open-app disposal 都要經 console helper 使用 process environment'
fi
require_literal 'App console launch 必須直接連 private FIFO' \
  "${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh" \
  '/usr/bin/xcrun simctl launch --console booted "$QA_BUNDLE_ID" "$@" \'
require_literal 'token environment 不得寫入 payload' "$SIM_REVIEW" 'session token process environment 不得寫入 payload、log 或 checkpoint。'

echo '=== Artifact identity ==='
require_literal '缺 artifact bundle id 解析' "$SIM_REVIEW" 'plutil -extract CFBundleIdentifier raw -o - "$QA_APP_ARTIFACT/Info.plist"'
BUNDLE_CHECK_LINE="$(grep -nF 'test "$QA_ARTIFACT_BUNDLE_ID" = "$QA_BUNDLE_ID"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
INSTALL_LINE="$(grep -nF 'xcrun simctl install booted "$QA_APP_ARTIFACT"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
if [ -n "$BUNDLE_CHECK_LINE" ] && [ -n "$INSTALL_LINE" ] && [ "$BUNDLE_CHECK_LINE" -lt "$INSTALL_LINE" ]; then
  pass
else
  fail 'artifact bundle id 必須在 install 前核對'
fi

echo '=== Marker safety ==='
if (
  set -e
  NUMERIC_ID='123456789012345'
  NUMERIC_ID_DIGEST="$(printf '%s' "$NUMERIC_ID" | shasum -a 256 | awk '{print $1}')"
  NORMALIZED_MARKER="$(
    python3 "$MARKER_FILTER" --normalize-expected-marker \
      "QA SCHED backfill scheduleId=$NUMERIC_ID generated=2 fromMs=100 toMs=200"
  )"
  printf '%s\n' "$NORMALIZED_MARKER" \
    | grep -Fq "scheduleId=sha256:$NUMERIC_ID_DIGEST"
  if printf '%s\n' "$NORMALIZED_MARKER" | grep -Fq "scheduleId=$NUMERIC_ID"; then
    exit 1
  fi

  DURATION_VALUE='120.5'
  DURATION_DIGEST="$(printf '%s' "$DURATION_VALUE" | shasum -a 256 | awk '{print $1}')"
  NORMALIZED_DURATION="$(
    python3 "$MARKER_FILTER" --normalize-expected-marker \
      "QA FOCUS visible elapsedMs=$DURATION_VALUE"
  )"
  printf '%s\n' "$NORMALIZED_DURATION" \
    | grep -Fq "elapsedMs=sha256:$DURATION_DIGEST"
  if printf '%s\n' "$NORMALIZED_DURATION" | grep -Fq "elapsedMs=$DURATION_VALUE"; then
    exit 1
  fi

  SINCE_VALUE='100'
  SINCE_DIGEST="$(printf '%s' "$SINCE_VALUE" | shasum -a 256 | awk '{print $1}')"
  NORMALIZED_SINCE="$(
    python3 "$MARKER_FILTER" --normalize-expected-marker \
      "QA BACKUP start sinceLastMs=$SINCE_VALUE"
  )"
  printf '%s\n' "$NORMALIZED_SINCE" \
    | grep -Fq "sinceLastMs=sha256:$SINCE_DIGEST"

  HUGE_INTEGER="1$(printf '%04999d' 0)"
  HUGE_OUTPUT="$(
    printf '%s\n' \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":$HUGE_INTEGER}" \
      | python3 "$MARKER_FILTER"
  )"
  test "$HUGE_OUTPUT" = 'QA RUNTIME MARKER REJECTED'
); then
  pass
else
  fail 'numeric identifier 與超長 JSON integer 必須 fail safe'
fi
require_literal 'marker filter 非零退出未標記失敗' "$SIM_REVIEW" 'QA_MARKER_FILTER_FAILED'
require_literal 'case marker validator 缺 offset' "$SIM_REVIEW" 'local qa_case_marker_offset="$1"'
require_literal 'case marker 仍會掃完整舊 log' "$SIM_REVIEW" 'tail -n "+$((qa_case_marker_offset + 1))" "$READY_MARKER_LOG"'

echo '=== Firebase probes and cleanup ==='
if [ -f "$FIRESTORE_PROBE" ]; then
  pass
else
  fail '缺 checked-in Firestore read seam'
fi
if [ -f "$AUTH_PROBE" ]; then
  pass
else
  fail '缺獨立 Auth absence probe'
fi
require_literal 'sim-review 未呼叫 checked-in Firestore seam' "$SIM_REVIEW" '"$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firestore-read.py"'
require_literal 'sim-review 未執行獨立 Auth absence probe' "$SIM_REVIEW" '"$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py"'
require_literal 'fixture cleanup 失敗沒有固定錯誤' "$SIM_REVIEW" 'QA_FIXTURE_CLEANUP_FAILED'
FIXTURE_CLEANUP_LINE="$(grep -nF 'if ! cleanup_qa_fixtures_if_required; then' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
DISPOSAL_LINE="$(grep -nF 'if ! dispose_qa_identity_if_required; then' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
if [ -n "$FIXTURE_CLEANUP_LINE" ] \
  && [ -n "$DISPOSAL_LINE" ] \
  && [ "$FIXTURE_CLEANUP_LINE" -lt "$DISPOSAL_LINE" ]; then
  pass
else
  fail 'trap 必須先 cleanup fixture 再 disposal'
fi

echo '=== Compile guard and blocked scenes ==='
require_literal 'sim-review 未呼叫 checked-in AppDelegate guard' "$SIM_REVIEW" '"$SESSION_CONTROL_PLANE_ROOT/scripts/qa-app-delegate-guard.py"'
if (
  set -e
  GUARD_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$GUARD_TEST_ROOT"' EXIT INT TERM

  printf '%s\n' \
    '#if !QA' \
    'import GoogleSignIn' \
    'return GIDSignIn.sharedInstance.handle(url)' \
    '#endif' \
    > "$GUARD_TEST_ROOT/safe.swift"
  python3 "$APP_DELEGATE_GUARD" "$GUARD_TEST_ROOT/safe.swift"

  printf '%s\n' \
    '#if !QA' \
    'import GoogleSignIn' \
    '#else' \
    'import GoogleSignIn' \
    '#endif' \
    '#if !QA' \
    'return GIDSignIn.sharedInstance.handle(url)' \
    '#endif' \
    > "$GUARD_TEST_ROOT/unsafe-else.swift"
  if python3 "$APP_DELEGATE_GUARD" "$GUARD_TEST_ROOT/unsafe-else.swift"; then
    exit 1
  fi

  printf '%s\n' \
    '#if !QA' \
    'import Foundation' \
    '#elseif QA' \
    'import GoogleSignIn' \
    '#endif' \
    '#if !QA' \
    'return GIDSignIn.sharedInstance.handle(url)' \
    '#endif' \
    > "$GUARD_TEST_ROOT/unsafe-elseif.swift"
  if python3 "$APP_DELEGATE_GUARD" "$GUARD_TEST_ROOT/unsafe-elseif.swift"; then
    exit 1
  fi

  printf '%s\n' \
    '#if SOME_FLAG' \
    'import Foundation' \
    '#elseif QA' \
    'import GoogleSignIn' \
    '#endif' \
    '#if !QA' \
    'return GIDSignIn.sharedInstance.handle(url)' \
    '#endif' \
    > "$GUARD_TEST_ROOT/unsafe-unknown-elseif.swift"
  if python3 "$APP_DELEGATE_GUARD" "$GUARD_TEST_ROOT/unsafe-unknown-elseif.swift"; then
    exit 1
  fi
); then
  pass
else
  fail 'AppDelegate guard 必須重現 else 與 elseif QA exposure'
fi
require_literal 'blocked scene 未逐場記錄' "$GAME_TEST" '只記錄該場次與相依者的 `blocked` 結果。'
require_literal '安全場次未明確繼續' "$GAME_TEST" '未依賴阻斷場次的安全場次繼續執行。'
forbid_literal '不得因單一 blocked scene 停整個 App session' "$GAME_TEST" '停止整個 App session'
require_literal 'R10 到 R12 必須永遠不執行' "$SIM_REVIEW" 'R10、R11 與 R12 永不執行。'

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
