#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GAME_TEST="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$TEST_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" --role test-run > "$GAME_TEST"
SIM_REVIEW="$(mktemp)"
trap 'rm -f "${SIM_REVIEW:-}" "${GAME_TEST:-}"' EXIT
python3 -B "$TEST_ROOT/scripts/render_qa_contract.py" --quality-root "${QA_QUALITY_TEST_ROOT:?}" > "$SIM_REVIEW"
RUNTIME="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh"
RESOLVER="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-firebase-project.sh"
MARKER_FILTER="${QA_QUALITY_TEST_ROOT:?}/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py"

PASS=0
FAIL=0

has_literal() {
  local name="$1"
  local file="$2"
  local literal="$3"

  if grep -Fq -- "$literal" "$file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    missing: $literal"
  fi
}

lacks_pattern() {
  local name="$1"
  local file="$2"
  local pattern="$3"

  if grep -Eiq -- "$pattern" "$file"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    forbidden pattern: $pattern"
  else
    PASS=$((PASS + 1))
  fi
}

has_adjacent_lines() {
  local name="$1"
  local file="$2"
  local first="$3"
  local second="$4"

  if awk -v first="$first" -v second="$second" '
    $0 == first {
      if ((getline next_line) > 0 && next_line == second) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
  fi
}

echo "=== QA identity payload contract ==="
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "payload 保留 qaGoogleAppId" "$skill" '`qaGoogleAppId`'
  has_literal "payload 保留 qaIdentityMode" "$skill" '`qaIdentityMode`'
  has_literal "payload 保留 qaFirebaseConfigSha256" "$skill" '`qaFirebaseConfigSha256`'
  has_literal "匿名身分模式固定" "$skill" '`disposable-anonymous`'
  has_literal "QA config digest 固定" "$skill" '`8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f`'
done

echo "=== Structured first-operation block ==="
has_literal "game-test 先讀 Quality structured block" "$GAME_TEST" '先讀取 Quality `no3_run_scripts/no0_index.md` 的 `結構化阻斷場次`。'
has_literal "game-test structured block exact keys" "$GAME_TEST" '`caseId`、`status`、`blockPhase` 與 `reason` 四個欄位。'
has_literal "game-test collects all run owners" "$GAME_TEST" '每個 selected QA case 必須收集所有承載它的 Rxx 場次。'
has_literal "game-test zero owner fails closed" "$GAME_TEST" '任一 selected QA case 找不到承載場次時停止。'
has_literal "game-test unions owner prerequisites" "$GAME_TEST" '每個承載場次都展開完整場次前置閉包，再取所有閉包的精確聯集。'
has_literal "game-test forbids arbitrary owner" "$GAME_TEST" '不得只選第一個、最新或最小的承載場次。'
has_literal "game-test block keys use Rxx union" "$GAME_TEST" '`caseId` 比對承載場次聯集與前置閉包聯集的 Rxx ID，不直接比對功能測項 ID。'
has_literal "game-test first-operation scene-only block" "$GAME_TEST" '命中 `first-operation` 時只記錄該場次與相依者的 `blocked` 結果。'
has_literal "game-test safe scenes continue" "$GAME_TEST" '未依賴阻斷場次的安全場次繼續執行。'
has_literal "game-test App Check reason exact" "$GAME_TEST" '`qa-app-check-isolation-unavailable` 表示 QA build 沒有可用的非 Production App Check attestation。'
has_literal "game-test R10 R12 fixed block" "$GAME_TEST" 'R10、R11 與 R12 固定使用 `qa-app-check-isolation-unavailable`。'
has_literal "game-test R10 R12 never execute" "$GAME_TEST" 'R10、R11 與 R12 只記 blocked 並永不執行。'
has_literal "game-test Production App Check forbidden" "$GAME_TEST" '`manual-device`、直接呼叫後端與重用 Production App Check 都不得繞過阻斷。'
has_literal "plan format structured block section" "$TEST_ROOT/references/quality/plan_format.md" '## 結構化阻斷場次'
has_literal "plan format structured block exact keys" "$TEST_ROOT/references/quality/plan_format.md" '`caseId`、`status`、`blockPhase` 與 `reason`。'
has_literal "plan format maps all QA case owners" "$TEST_ROOT/references/quality/plan_format.md" '`test-run` 必須收集 selected QA case 的所有承載場次與各自完整前置閉包，再比對結構化阻斷。'
has_literal "plan format zero owner stops" "$TEST_ROOT/references/quality/plan_format.md" 'selected QA case 沒有承載場次時必須停止。'
has_literal "generation structured block mirror" "$TEST_ROOT/references/quality/generation_procedure.md" '結構化阻斷場次在索引與各自 runbook 檔頭逐字鏡射。'
has_literal "generation structured block first operation" "$TEST_ROOT/references/quality/generation_procedure.md" '`status` 固定為 `blocked`，`blockPhase` 固定為 `first-operation`。'

echo "=== SQLite-local bundle binding ==="
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "sqlite-local 鎖 payload bundle" "$skill" 'QA_BUNDLE_ID 只取自 payload 的 `qaBundleId`。'
  has_literal "sqlite-local readiness 鎖 bundle" "$skill" 'sqlite-local readiness 與每次 probe 都必須使用 payload 鎖定的 `qaBundleId`。'
  has_literal "sqlite-local 拒絕 Production bundle" "$skill" 'Production bundle id `com.almightyken0425.susugigiapp` 為明確拒絕值。'
  has_literal "query_local_db 禁預設 bundle" "$skill" '`query_local_db.sh` 未顯式帶 bundle id 時停止。'
  has_literal "sqlite-local readiness 經 wrapper" "$skill" 'sqlite-local readiness 必須執行 `run_qa_sqlite_local_probe path`。'
  has_literal "sqlite-local probe 經 wrapper" "$skill" '每次 sqlite-local probe 都必須經過 `run_qa_sqlite_local_probe`。'
done
has_literal "test-run 共用 SQLite 執行來源" "$GAME_TEST" \
  '[SQLite 綁定程式](ios_runtime/sqlite_binding_1.sh)'
lacks_pattern "test-run 不保留候選 Quality 直接執行" "$GAME_TEST" \
  'bash "\$QUALITY_ROOT/no2_qa_tools/'
has_literal "sim-review query_local_db 使用 session Quality root" "$SIM_REVIEW" \
  'bash "$SESSION_QUALITY_ROOT/no2_qa_tools/query_local_db.sh" \'
has_literal "sim-review query_local_db 顯式 bundle id" "$SIM_REVIEW" \
  '--bundle-id "$QA_BUNDLE_ID" \'

echo "=== READY identity gate ==="
has_literal "game-test 驗 READY identityMode" "$GAME_TEST" 'READY identityMode 必須為 `disposable-anonymous`。'
has_literal "game-test 驗 READY isAnonymous" "$GAME_TEST" 'READY isAnonymous 必須為 `true`。'
has_literal "game-test 寫入前 READY gate" "$GAME_TEST" '第一個 seed 或 write 前必須通過 READY 身分閘門。'
has_literal "sim-review 驗 READY identityMode" "$SIM_REVIEW" 'READY identityMode 必須為 `disposable-anonymous`。'
has_literal "sim-review 驗 READY isAnonymous" "$SIM_REVIEW" 'READY isAnonymous 必須為 `true`。'
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "READY identityHash 固定 64 hex" "$skill" 'READY identityHash 必須為六十四字元小寫十六進位。'
  has_literal "READY identityHash 綁 native proof" "$skill" 'READY identityHash 必須逐字等於 native session proof 的 uid hash。'
  has_literal "READY 禁 raw Firebase uid" "$skill" 'READY 不得包含 raw Firebase uid。'
done
has_literal "sim-review 保存驗證後 READY identityHash" "$RUNTIME" 'READY_IDENTITY_HASH="$qa_identity"'
has_literal "sim-review 驗 identityHash 格式" "$SIM_REVIEW" '[[ "$READY_IDENTITY_HASH" =~ ^[0-9a-f]{64}$ ]]'
has_literal "operation READY 缺 identityHash fail closed" "$SIM_REVIEW" 'operation READY identityHash 缺失判定 `fail`。'
has_literal "open-app READY 缺 identityHash fail closed" "$SIM_REVIEW" 'open-app READY identityHash 缺失判定 `fail`。'
has_literal "post-auth settled 由 validated READY 推導" "$SIM_REVIEW" '`AUTH_PROVIDER_POST_AUTH_SETTLED=1` 只可由 exact validated operation READY 推導。'
has_literal "post-auth settled by construction" "$SIM_REVIEW" 'QaRuntimeBridge 只在 AuthContext post-auth 完成並關閉 isLoading 後輸出 operation READY。'

echo "=== Firestore probe identity binding ==="
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "Firestore 前列舉 QA SQLite users.id" "$skill" '首次 firestore-read 前必須列舉 canonical QA SQLite 的 `users.id`。'
  has_literal "bootstrap 後不得立即 bind" "$skill" 'bootstrap READY 後不得立即 bind SQLite。'
  has_literal "binding 等 authorized post-auth" "$skill" '首次 firestore-read bind 必須晚於首個 authorized operation READY 與 AuthProvider post-auth 收斂。'
  has_literal "無 operation 時先 open-app" "$skill" 'firestore-read 前沒有 prepare、inspect 或 open-app 時必須先執行 token-bound open-app operation。'
  has_literal "Firestore SQLite 列舉鎖 qaBundleId" "$skill" 'SQLite 列舉必須使用 payload 鎖定的 `qaBundleId`。'
  has_literal "候選 uid 僅本機 hash" "$skill" '每個候選 uid 只在本機計算 SHA-256。'
  has_literal "identityHash exact-one match" "$skill" '候選 hash 必須與 READY identityHash exact-one match。'
  has_literal "零 match fail closed" "$skill" '零筆 match 必須 fail-closed。'
  has_literal "多 match fail closed" "$skill" '多筆 match 必須 fail-closed。'
  has_literal "raw uid 只留 shell memory" "$skill" '命中的 raw uid 只准留在 shell memory 的 `QA_SESSION_UID`。'
  has_literal "Firestore path 綁 QA_SESSION_UID" "$skill" '所有 firestore-read resource path 必須由 `QA_SESSION_UID` 衍生。'
  has_literal "不得選 newest 文件" "$skill" '禁止依 newest 文件推定身分。'
  has_literal "不得選任意文件" "$skill" '禁止依任意文件推定身分。'
  has_literal "raw uid 不得持久化" "$skill" 'log、session 報告與持久工件不得包含 raw uid。'
  has_literal "SQLite candidates 不得直接輸出" "$skill" 'SQLite candidates 必須以 command substitution 捕獲，不得直接輸出。'
  has_literal "SQLite candidates stdout stderr 全捕獲" "$skill" 'SQLite candidates 的 stdout 與 stderr 必須完整捕獲。'
  has_literal "Firestore output 不得直接 echo" "$skill" '不得直接 echo Firestore probe 原始輸出。'
  has_literal "Firestore output 僅在 session 判讀" "$skill" 'Firestore probe 判讀只在 shell memory 或本次 temporary file 執行。'
  has_literal "Firestore stdout stderr 全捕獲" "$skill" 'Firestore driver 的 stdout 與 stderr 必須完整捕獲。'
  has_literal "Firestore 只輸出 allowlisted facts" "$skill" '可見輸出只包含 allowlisted facts。'
  has_literal "Firestore 可見證據先遮蔽 UID" "$skill" '可見 log 與報告必須先以 `[QA_SESSION_UID]` 取代 raw uid。'
  has_literal "Firestore temporary output 必須清除" "$skill" 'Firestore probe 使用 temporary file 時 cleanup 必須刪除。'
  has_literal "Firestore error 固定安全碼" "$skill" 'Firestore probe 失敗只回固定安全碼。'
  has_literal "Firestore 不透傳 driver 訊息" "$skill" '不得回傳 Firestore driver 原始錯誤或 command line。'
  has_literal "zero multi 不列候選" "$skill" 'zero 或 multi match 不得列出候選 uid。'
  has_literal "disposal 僅刪 Auth" "$skill" 'disposal 只銷毀 Firebase Auth 身分。'
  has_literal "disposal 不代表 cloud data cleanup" "$skill" 'disposal 不代表 Firestore 測試資料已清除。'
  has_literal "disposal 後清除 raw uid" "$skill" '正常與 cleanup disposal 嘗試後都必須清除 `QA_SESSION_UID`。'
done
has_literal "sim-review 初始化 QA_SESSION_UID" "$SIM_REVIEW" 'QA_SESSION_UID=""'
has_literal "sim-review SQLite exact-one binder" "$SIM_REVIEW" 'bind_qa_session_uid_from_sqlite() {'
has_literal "sim-review canonical users.id query" "$SIM_REVIEW" 'SELECT id FROM users WHERE _status != '\''deleted'\'' ORDER BY id;'
has_literal "sim-review 本機 SHA-256" "$SIM_REVIEW" 'printf '\''%s'\'' "$qa_candidate_uid" | /usr/bin/shasum -a 256 | /usr/bin/awk '\''{print $1}'\'''
has_literal "sim-review match count 必須為一" "$SIM_REVIEW" '[ "$qa_identity_match_count" -ne 1 ]'
has_literal "sim-review binding 成功才更新 UID" "$SIM_REVIEW" 'QA_SESSION_UID="$qa_matched_uid"'
has_literal "sim-review Firestore read wrapper" "$SIM_REVIEW" 'run_qa_firestore_read() {'
has_literal "sim-review profile 封閉 mapping" "$SIM_REVIEW" 'resolve_qa_firestore_profile() {'
has_literal "sim-review semantic profile driver" "$SIM_REVIEW" '--profile "$QA_FIRESTORE_PROFILE"'
has_literal "sim-review SQLite output command substitution" "$SIM_REVIEW" 'qa_sqlite_users_output="$('
has_literal "sim-review SQLite stderr 同時捕獲" "$SIM_REVIEW" 'SELECT id FROM users WHERE _status != '\''deleted'\'' ORDER BY id;" 2>&1'
has_literal "sim-review Firestore output command substitution" "$SIM_REVIEW" 'qa_firestore_probe_output="$('
has_literal "sim-review Firestore stderr 同時捕獲" "$SIM_REVIEW" 'qa_firestore_read_driver "${qa_firestore_driver_arguments[@]}" 2>&1'
has_literal "sim-review Firestore allowlisted renderer" "$SIM_REVIEW" 'render_qa_firestore_allowlisted_facts_in_memory "$qa_firestore_probe_output"'
has_literal "sim-review renderer error 不得透傳" "$SIM_REVIEW" 'render_qa_firestore_allowlisted_facts_in_memory "$qa_firestore_probe_output" 2>/dev/null'
has_literal "sim-review Firestore output 固定遮蔽" "$SIM_REVIEW" 'qa_firestore_visible_output="${qa_firestore_visible_output//"$QA_SESSION_UID"/[QA_SESSION_UID]}"'
has_literal "sim-review Firestore 固定錯誤碼" "$SIM_REVIEW" 'QA_FIRESTORE_PROBE_FAILED'
has_literal "sim-review binding 固定錯誤碼" "$SIM_REVIEW" 'QA_FIRESTORE_IDENTITY_BINDING_FAILED'
has_literal "sim-review stateful lifecycle 同 shell" "$SIM_REVIEW" '整個 stateful lifecycle 必須在同一個 long-lived shell process 與 session 執行。'
has_literal "sim-review state 不拆 exec" "$SIM_REVIEW" 'session token、identityHash 與 `QA_SESSION_UID` 不得拆到獨立 exec。'
has_literal "sim-review token uid 永不持久化" "$SIM_REVIEW" 'session token、raw Firebase uid 與 `QA_SESSION_UID` 永不得寫入任何檔案。'
has_literal "sim-review identity hash 不重建" "$SIM_REVIEW" 'identityHash 不得 export 或重建。'
lacks_pattern "不得 echo raw UID 變數" "$SIM_REVIEW" 'echo[^\n]*(QA_SESSION_UID|qa_candidate_uid)'
lacks_pattern "不得 echo Firestore 原始輸出" "$SIM_REVIEW" 'echo[^\n]*qa_firestore_probe_output'
lacks_pattern "不得 printf Firestore 原始輸出" "$SIM_REVIEW" 'printf[^\n]*qa_firestore_probe_output'

OPERATION_READY_LINE="$(grep -nF '[ "$AUTHORIZED_OPERATION_READY_CONFIRMED" = 1 ]' "$RUNTIME" | tail -n 1 | cut -d: -f1 || true)"
POST_AUTH_LINE="$(grep -nF '[ "$AUTH_PROVIDER_POST_AUTH_SETTLED" = 1 ]' "$RUNTIME" | tail -n 1 | cut -d: -f1 || true)"
BIND_CALL_LINE="$(grep -nF 'bind_qa_session_uid_from_sqlite || return 1' "$RUNTIME" | head -n 1 | cut -d: -f1 || true)"
FIRESTORE_CALL_LINE="$(grep -nF 'run_qa_firestore_read || return 1' "$RUNTIME" | head -n 1 | cut -d: -f1 || true)"
if [ -n "$OPERATION_READY_LINE" ] \
  && [ -n "$POST_AUTH_LINE" ] \
  && [ -n "$BIND_CALL_LINE" ] \
  && [ -n "$FIRESTORE_CALL_LINE" ] \
  && [ "$OPERATION_READY_LINE" -lt "$BIND_CALL_LINE" ] \
  && [ "$POST_AUTH_LINE" -lt "$BIND_CALL_LINE" ] \
  && [ "$BIND_CALL_LINE" -lt "$FIRESTORE_CALL_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL Firestore binding 必須在 authorized post-auth 後、first wrapper call 前"
fi

IDENTITY_BIND_BLOCK="$(sed -n '/^bind_qa_session_uid_from_sqlite() {$/,/^}$/p' "$SIM_REVIEW")"
if (
  set -e
  BIND_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$BIND_TEST_ROOT"' EXIT INT TERM
  BIND_STDOUT_FILE="$BIND_TEST_ROOT/stdout"
  eval "$IDENTITY_BIND_BLOCK"
  MATCH_UID="qa-session-user"
  OTHER_UID="stale-user"
  READY_IDENTITY_HASH="$(printf '%s' "$MATCH_UID" | shasum -a 256 | awk '{print $1}')"
  SQLITE_ROWS=""
  SQLITE_QUERY_FAIL=0

  run_qa_sqlite_local_probe() {
    test "$1" = sql
    test "$2" = "SELECT id FROM users WHERE _status != 'deleted' ORDER BY id;"
    [ "$SQLITE_QUERY_FAIL" = 0 ] || return 1
    printf '%s\n' id ---------------- "$SQLITE_ROWS"
  }

  SQLITE_ROWS="$(printf '%s\n%s' "$OTHER_UID" "$MATCH_UID")"
  bind_qa_session_uid_from_sqlite > "$BIND_STDOUT_FILE"
  test ! -s "$BIND_STDOUT_FILE"
  test "$QA_SESSION_UID" = "$MATCH_UID"

  SQLITE_ROWS="$OTHER_UID"
  if bind_qa_session_uid_from_sqlite; then
    exit 1
  fi
  test "$QA_SESSION_UID" = "$MATCH_UID"

  SQLITE_ROWS="$(printf '%s\n%s' "$MATCH_UID" "$MATCH_UID")"
  if bind_qa_session_uid_from_sqlite; then
    exit 1
  fi
  test "$QA_SESSION_UID" = "$MATCH_UID"

  SQLITE_QUERY_FAIL=1
  if bind_qa_session_uid_from_sqlite; then
    exit 1
  fi
  test "$QA_SESSION_UID" = "$MATCH_UID"
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL Firestore exact-one identity binding 動態契約"
fi

for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "R10 到 R12 runtime 不得建立 transaction index path" "$skill" 'R10 至 R12 永久受阻，因此 runtime 不得建立、解析或讀取 transaction index path。'
  lacks_pattern "永久受阻場次不得保留 transaction capture runtime" "$skill" 'capture_qa_original_transaction_id_from_session_entitlement'
  lacks_pattern "永久受阻場次不得保留 transaction read runtime" "$skill" 'run_qa_txn_index_exact_doc_probe'
  lacks_pattern "永久受阻場次不得保留 transaction resource path" "$skill" 'txnIndex/\$QA_ORIGINAL_TRANSACTION_ID'
done

echo "=== No-write capability bootstrap ==="
has_literal "game-test bootstrap 例外只有 qa-command qa-probe" "$GAME_TEST" '受阻能力例外只接受 `qa-command` 與 `qa-probe`。'
has_literal "game-test bootstrap 前靜態全綠" "$GAME_TEST" 'selected cases 使用 qa-command 或 qa-probe 時，兩者的靜態探測必須全數通過。'
has_literal "game-test 其他受阻仍停止" "$GAME_TEST" '其他受阻能力仍立即停止。'
has_literal "game-test bootstrap 不寫入" "$GAME_TEST" 'bootstrap launch 不得執行 prepare、inspect 或 dispose。'
has_literal "game-test READY 後 session 提升" "$GAME_TEST" 'READY 通過後只提升當次 session 的 qa-command 與 qa-probe。'
has_literal "game-test 不改持久狀態" "$GAME_TEST" 'Quality 的持久能力狀態維持受阻。'
has_literal "sim-review bootstrap 只傳 requestId argument" "$SIM_REVIEW" 'bootstrap launch 只傳 requestId argument。'
has_literal "sim-review bootstrap 同 requestId" "$SIM_REVIEW" 'bootstrap READY requestId 必須等於 `BOOTSTRAP_REQUEST_ID`。'
has_literal "sim-review bootstrap 禁 RESULT" "$SIM_REVIEW" 'bootstrap requestId 出現任何 RESULT 判定 `fail`。'
has_literal "sim-review session 提升" "$SIM_REVIEW" 'session 提升只適用 `qa-command` 與 `qa-probe`。'
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "App session 第一次 launch 固定 bootstrap" "$skill" '每個 App session 的第一次 launch 固定為身分 bootstrap。'
  has_literal "bootstrap 使用 dedicated root" "$skill" '身分 bootstrap launch 必須路由 `QaIdentityBootstrapApp`。'
  has_literal "bootstrap 建立全新匿名 Auth" "$skill" '`QaIdentityBootstrapApp` 先刪除 stale anonymous Auth，再建立新的匿名 Firebase Auth。'
  has_literal "bootstrap 不得恢復舊匿名 Auth" "$skill" 'bootstrap 不得恢復或重用舊匿名身分。'
  has_literal "bootstrap 禁止 App 資料寫入" "$skill" 'READY 前不得執行 App 資料 seed、資料庫寫入或同步。'
  has_literal "operation READY 後才能 mount App" "$skill" 'operation launch 只能在 READY 通過後 mount `QaApp`。'
  has_literal "launch plan 恰一種" "$skill" '每次 launch 恰好屬於 bootstrap、open-app、prepare、inspect 或 dispose 其中一種。'
  has_literal "bootstrap 唯一零 operation" "$skill" 'bootstrap 是唯一不帶 operation flag 的 launch。'
  has_literal "prepare inspect 禁同 launch" "$skill" 'prepare 與 inspect 不得在同一次 launch 傳入。'
done
has_literal "bootstrap launch process environment token" "$RUNTIME" 'SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN="$qa_session_token" \'
has_literal "bootstrap launch requestId" "$RUNTIME" '--qa-request-id "$BOOTSTRAP_REQUEST_ID"'
lacks_pattern "bootstrap launch 不得傳 token argument" "$SIM_REVIEW" '--qa-session-token[[:space:]]+"\$QA_SESSION_TOKEN"'

echo "=== Manual-only App operation ==="
for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "manual-only 使用 open-app operation" "$skill" 'seed 與 inspect 都為 none 且 case 需要開 App 時，必須使用 open-app operation。'
  has_literal "manual-only 禁 requestId-only launch" "$skill" 'manual-only App launch 不得使用 requestId-only 或無 flag launch。'
done
has_literal "game-test 產生 open-app arguments" "$GAME_TEST" 'manual-only App case 的 `qaLaunchArguments` 固定為 `--qa-open-app true`。'
has_literal "sim-review allowlist open-app" "$SIM_REVIEW" 'qaLaunchArguments allowlist 只接受 prepare、inspect 與 `--qa-open-app true`。'
has_literal "open-app requestId 高熵" "$SIM_REVIEW" 'open-app operation 使用高熵且不重用的 requestId。'
has_literal "open-app launch requestId" "$RUNTIME" '--qa-request-id "$OPEN_APP_REQUEST_ID"'
has_literal "open-app launch flag" "$RUNTIME" '--qa-open-app true'

echo "=== QA session proof ==="
has_literal "session token 高熵來源" "$RUNTIME" 'QA_SESSION_TOKEN="$(/usr/bin/openssl rand -hex 32)"'
has_literal "session token 固定 64 hex" "$SIM_REVIEW" '[[ "$QA_SESSION_TOKEN" =~ ^[0-9a-f]{64}$ ]]'
has_literal "session token 不得輸出" "$SIM_REVIEW" 'QA session token 不得輸出到 stdout、stderr 或 log。'
has_literal "session token 不得進 report" "$SIM_REVIEW" 'QA session token 不得寫入完成回報。'
has_literal "session token 不得進 crash artifact" "$SIM_REVIEW" 'QA session token 不得寫入 crash artifact。'
has_literal "proof 綁 token hash" "$SIM_REVIEW" 'native session proof 必須綁定 token hash。'
has_literal "proof 綁 uid hash" "$SIM_REVIEW" 'native session proof 必須綁定 uid hash。'
has_literal "proof 綁 TTL" "$SIM_REVIEW" 'native session proof 必須包含 TTL。'
has_literal "proof 綁 consumed hash" "$SIM_REVIEW" 'native session proof 必須保存 consumed request 與 operation hash。'
has_literal "operation 原子 consume" "$SIM_REVIEW" 'operation gate 必須在 mount `QaApp` 前原子 consume proof。'
has_literal "operation expiry fail closed" "$SIM_REVIEW" 'operation proof 缺失、過期、身分不符或重放時必須 fail-closed。'
has_literal "operation expiry 禁 mount" "$SIM_REVIEW" 'operation proof 過期時不得 mount `QaApp`。'
has_literal "disposal 進 disposing" "$SIM_REVIEW" 'disposal 必須驗證同一 session token，再先轉為 disposing。'
has_literal "disposal 忽略 expiry" "$SIM_REVIEW" 'disposal 必須忽略 proof expiry，避免過期 proof 阻斷帳號清理。'
has_literal "disposal 保留身分驗證" "$SIM_REVIEW" 'disposal 仍必須驗證 token hash、uid hash 與 proof state。'
has_literal "disposal 身分不符 fail closed" "$SIM_REVIEW" 'token hash、uid hash 或 proof state 不符時 disposal fail-closed。'
has_literal "operation requestId 高熵" "$SIM_REVIEW" '每個 operation 使用高熵且不重用的 requestId。'
lacks_pattern "不得 echo session token" "$SIM_REVIEW" 'echo[^\n]*QA_SESSION_TOKEN'
lacks_pattern "payload 不得持久化 session token" "$SIM_REVIEW" 'qaSessionToken'
lacks_pattern "disposal 不得要求 TTL" "$SIM_REVIEW" 'dispose native gate 驗證 token hash、uid hash 與 TTL'
lacks_pattern "proof expiry 不得全域阻斷" "$SIM_REVIEW" '^-[[:space:]]+proof 缺失、過期、身分不符或重放時停止。$'

echo "=== Transient READY marker log ==="
has_literal "marker log session owned" "$SIM_REVIEW" 'identityHash 只允許出現在本次 session 的 transient READY marker log。'
has_literal "token raw uid 永不寫檔" "$SIM_REVIEW" 'session token、raw Firebase uid 與 `QA_SESSION_UID` 永不得寫入任何檔案。'
has_literal "identityHash 禁持久通道" "$SIM_REVIEW" 'identityHash 不得進入 payload、checkpoint、完成回報、crash artifact 或 persistent artifact。'
has_literal "marker log every exit cleanup" "$SIM_REVIEW" 'transient READY marker log 必須在每個 exit path 由 cleanup 刪除。'
has_literal "marker temporary root 解析 symlink" "$SIM_REVIEW" 'QA_MARKER_TEMP_ROOT="$(cd -P "${TMPDIR:-/tmp}" && pwd -P)"'
has_literal "marker temporary root 必須為絕對路徑" "$SIM_REVIEW" '*) printf '\''%s\n'\'' QA_MARKER_TEMP_ROOT_INVALID >&2; exit 1 ;;'
for trusted_marker_tool in /bin/rm /bin/rmdir /usr/bin/mkfifo /usr/bin/mktemp; do
  has_literal "marker core tool 經 trusted metadata gate" "$SIM_REVIEW" "  $trusted_marker_tool \\"
done
has_literal "marker log private mktemp" "$SIM_REVIEW" 'READY_MARKER_LOG="$(/usr/bin/mktemp "$QA_MARKER_TEMP_ROOT/sim-review-ready.log.XXXXXX")"'
has_literal "marker stream private mktemp" "$SIM_REVIEW" 'METRO_STREAM_TMP="$(/usr/bin/mktemp -d "$QA_MARKER_TEMP_ROOT/sim-review-stream.XXXXXX")"'
has_literal "marker fifo trusted tool" "$SIM_REVIEW" '/usr/bin/mkfifo "$METRO_STREAM_FIFO"'
has_literal "marker fifo cleanup trusted tool" "$SIM_REVIEW" '/bin/rm -f "$METRO_STREAM_FIFO"'
has_literal "marker directory cleanup trusted tool" "$SIM_REVIEW" '/bin/rmdir "$METRO_STREAM_TMP"'
has_literal "marker log cleanup trusted tool" "$SIM_REVIEW" '/bin/rm -f "$READY_MARKER_LOG"'
lacks_pattern "marker log 不得使用 symlinked /tmp literal" "$SIM_REVIEW" 'mktemp[^\n]*/tmp/sim-review-(ready|stream)'
has_literal "marker log 變數初始化" "$SIM_REVIEW" 'READY_MARKER_LOG=""'
has_literal "Metro stream 先進 private fifo" "$SIM_REVIEW" '> "$METRO_STREAM_FIFO" 2>&1 &'
has_literal "filter 才能寫 marker log" "$SIM_REVIEW" 'python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py" \'
has_literal "filter output 寫 marker log" "$SIM_REVIEW" '> "$READY_MARKER_LOG" &'
has_literal "selected golden marker 明確傳入" "$SIM_REVIEW" 'QA_MARKER_FILTER_ARGS+=(--allow-golden-marker "$qa_marker_family")'
has_literal "selected marker normalization seam" "$SIM_REVIEW" '--normalize-expected-marker "$qa_log_marker"'
has_literal "normalized expected marker array" "$SIM_REVIEW" 'QA_NORMALIZED_LOG_MARKERS+=("$qa_normalized_marker")'
has_literal "marker exact compare" "$SIM_REVIEW" '[ "$qa_runtime_marker" = "$qa_expected_marker" ]'
has_literal "marker prefix compare" "$SIM_REVIEW" '"$qa_expected_marker"|"$qa_expected_marker "*)'
has_literal "normalized marker validation call" "$SIM_REVIEW" 'validate_selected_qa_markers'
has_literal "golden family 鎖 Quality allowlist" "$SIM_REVIEW" 'QA_MARKER_GOLDEN_FAMILY_ALLOWLIST='
has_literal "source 禁 raw UID marker" "$SIM_REVIEW" 'QA_MARKER_SOURCE_FORBIDDEN_IDENTITY_FIELD'
has_literal "source 掃描所有 console call" "$SIM_REVIEW" 'candidate source 的所有 console call 都必須拒絕 UID 或 session token 參數，即使 marker 由變數傳入。'
has_literal "source 固定 uid 文案可接受" "$SIM_REVIEW" '固定 string literal 的 uid 字樣不視為身分值。'
has_literal "source expression 仍阻擋" "$SIM_REVIEW" 'console argument expression 與 template interpolation 仍必須掃描身分值。'
has_literal "RESULT operation-specific schema" "$SIM_REVIEW" '`QA RESULT` 必須依 bootstrap、launch、prepare、inspect 或 dispose 套用 operation-specific exact schema。'
has_literal "evidence string deterministic digest" "$SIM_REVIEW" 'inspect evidence 的 actual 與 expected 為字串時，filter 必須在寫檔前改為 deterministic SHA-256 digest。'
has_literal "golden per-family schema" "$SIM_REVIEW" 'golden marker 必須依 family 套用 event 與 field allowlist。'
has_literal "golden free string digest" "$SIM_REVIEW" 'golden marker 的自由字串 field value 必須在寫檔前改為 deterministic SHA-256 digest。'
has_literal "未過濾輸出不得可見" "$SIM_REVIEW" 'unfiltered App 或 Metro stream 不得寫檔或輸出到可見通道。'
has_literal "App console 直接進安全 FIFO" "$RUNTIME" '/usr/bin/xcrun simctl launch --console booted "$QA_BUNDLE_ID" "$@" \'
has_literal "App console PID 受控" "$SIM_REVIEW" 'QA_APP_CONSOLE_PID=""'
has_literal "App console bounded cleanup" "$SIM_REVIEW" 'stop_qa_app_console_capture_with_deadline() {'
lacks_pattern "Metro 不得重複轉送 client logs" "$SIM_REVIEW" '^[[:space:]]*--client-logs([[:space:]]|\\|$)'
has_literal "filter pid bounded cleanup" "$SIM_REVIEW" 'stop_marker_filter_with_deadline "$METRO_FILTER_PID"'
has_literal "filter deadline 後強制停止" "$SIM_REVIEW" 'kill -KILL "$marker_filter_pid" 2>/dev/null || true'
has_literal "cleanup 等待 Metro 停止" "$SIM_REVIEW" 'wait "$METRO_PID" 2>/dev/null || true'
has_literal "cleanup 刪 marker log" "$SIM_REVIEW" 'rm -f "$READY_MARKER_LOG"'
has_literal "cleanup 驗 marker log 不存在" "$SIM_REVIEW" '[ ! -e "$READY_MARKER_LOG" ]'
has_literal "完成回報 marker log 已刪" "$SIM_REVIEW" '回報 transient READY marker log 已刪除。'
has_literal "runtime rejection sentinel 固定" "$MARKER_FILTER" 'RUNTIME_MARKER_REJECTION_SENTINEL = "QA RUNTIME MARKER REJECTED"'
has_literal "native diagnostic exact allowlist" "$MARKER_FILTER" 'SAFE_NATIVE_DIAGNOSTICS = frozenset('
has_literal "bootstrap 失敗回報 native 分類" "$RUNTIME" 'qa_runtime_report_native_diagnostics "$qa_offset" || true'
has_literal "runtime window validator actual definition" "$SIM_REVIEW" 'require_runtime_marker_window_clean() {'
has_literal "runtime window validator exact sentinel" "$SIM_REVIEW" "grep -Fqx -- 'QA RUNTIME MARKER REJECTED'"
has_literal "runtime quiet window actual definition" "$SIM_REVIEW" 'wait_for_runtime_marker_quiet_window() {'
has_literal "runtime session taint actual definition" "$SIM_REVIEW" 'require_runtime_marker_session_clean() {'
has_literal "runtime session taint state" "$SIM_REVIEW" 'RUNTIME_MARKER_SESSION_TAINTED=0'
has_literal "runtime session start offset" "$SIM_REVIEW" 'RUNTIME_MARKER_SESSION_START_OFFSET="$(wc -l < "$READY_MARKER_LOG")"'
has_literal "filter 記住 READY identityHash" "$SIM_REVIEW" 'filter 記住第一筆通過驗證的 READY identityHash。'
has_literal "identity digest collision emit sentinel" "$SIM_REVIEW" '任何 RESULT 或 golden marker 正規化 digest 等於 READY identityHash 時輸出 sentinel。'
has_literal "pre-ready success 與 golden fail closed" "$SIM_REVIEW" '第一筆 valid READY 前，所有成功 prepare／inspect RESULT 與 selected golden marker 必須輸出 sentinel。'
has_literal "pre-ready failure exact allowlist" "$SIM_REVIEW" '第一筆 valid READY 前只允許 fixed-schema bootstrap／launch／dispose failure RESULT。'
has_literal "expected marker identity digest fail closed" "$SIM_REVIEW" 'selected expected marker 的 digest 等於 READY identityHash 時停止。'
has_literal "所有 READY RESULT 先驗 sentinel" "$SIM_REVIEW" '每個 READY 與 RESULT validator 必須先檢查自身 offset window 不含 sentinel。'
has_literal "sentinel 與合法 pass 共存仍 fail" "$SIM_REVIEW" 'offset window 含 sentinel 時即使另有合法 pass 也停止。'
has_literal "session taint 不可清除" "$SIM_REVIEW" 'session taint 一旦成立不得在本次 lifecycle 清除。'
has_literal "cleanup drain 後重驗 taint" "$SIM_REVIEW" 'cleanup 停止 filter 後必須重驗整個 session marker window。'
has_literal "bootstrap READY sentinel gate" "$SIM_REVIEW" 'bootstrap READY validator 在接受成功前必須對 offset window 執行 `require_runtime_marker_window_clean`。'
has_literal "bootstrap READY stabilization" "$SIM_REVIEW" 'bootstrap READY candidate 出現後必須終止 App 並等待 bounded drain quiet window。'
has_literal "operation READY RESULT sentinel gate" "$SIM_REVIEW" 'operation READY 與 RESULT validator 在接受成功前必須對各自 offset window 執行 `require_runtime_marker_window_clean`。'
has_literal "operation RESULT stabilization" "$SIM_REVIEW" 'prepare 或 inspect 的 RESULT candidate 出現後必須終止 App 並等待 bounded drain quiet window。'
has_literal "operation READY 延後接受" "$SIM_REVIEW" 'operation READY candidate 只允許繼續等待 RESULT，不得提前提升 session。'
has_literal "open-app READY sentinel gate" "$SIM_REVIEW" 'open-app READY validator 在接受成功前必須對 offset window 執行 `require_runtime_marker_window_clean`。'
has_literal "open-app READY stabilization" "$SIM_REVIEW" 'open-app READY candidate 必須經 bounded quiet window 後才可開始 UI 操作。'
has_literal "dispose RESULT sentinel gate" "$SIM_REVIEW" 'dispose RESULT validator 在接受成功前必須對 offset window 執行 `require_runtime_marker_window_clean`。'
has_literal "dispose RESULT stabilization" "$SIM_REVIEW" 'dispose RESULT candidate 出現後必須終止 App 並等待 bounded drain quiet window。'
lacks_pattern "不得固定重用 Metro log" "$SIM_REVIEW" '/tmp/sim-review-metro\.log'
lacks_pattern "不得禁止 identityHash transient log" "$SIM_REVIEW" '三者不得 export、寫檔或重建。'
lacks_pattern "不得 tee 未過濾 Metro stream" "$SIM_REVIEW" '(^|[[:space:]])tee([[:space:]]|$)'

if (
  set -e
  RAW_UID='rawQaUser1234567890abcdef'
  RAW_UID_DIGEST="$(printf '%s' "$RAW_UID" | shasum -a 256 | awk '{print $1}')"
  READY_HASH="$RAW_UID_DIGEST"
  FILTERED_OUTPUT="$(
    printf '%s\n' \
      'Metro ready on port 8081' \
      "FirebaseError failed path=/users/$RAW_UID" \
      "QA FOCUS visible uid=$RAW_UID elapsedMs=42" \
      "QA FOCUS $RAW_UID" \
      'QA UNKNOWN should-not-survive' \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"unsafe-ready\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\",\"uid\":\"$RAW_UID\"}" \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$RAW_UID\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"}" \
      "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"unsafe-result\",\"operation\":\"inspect\",\"value\":\"check\",\"result\":{\"ok\":true,\"identityHash\":\"$READY_HASH\"}}" \
      "LOG QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"inspect-44444444444444444444444444444444\",\"operation\":\"inspect\",\"value\":\"accounting.fixture-summary\",\"result\":{\"ok\":true,\"runId\":\"qa-abcdefgh-4\",\"value\":{\"schema\":\"qa.evidence/v1\",\"checkId\":\"accounting.fixture-summary\",\"verdict\":\"pass\",\"facts\":{\"foo\":\"$RAW_UID\"}}}}" \
      "LOG QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-11111111111111111111111111111111\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"}" \
      "LOG QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"inspect-55555555555555555555555555555555\",\"operation\":\"inspect\",\"value\":\"accounting.fixture-summary\",\"result\":{\"ok\":true,\"runId\":\"qa-abcdefgh-5\",\"value\":{\"schema\":\"qa.evidence/v1\",\"checkId\":\"accounting.fixture-summary\",\"verdict\":\"pass\",\"facts\":[{\"key\":\"accounts.signature\",\"actual\":\"$RAW_UID\",\"expected\":\"safe-reference\",\"pass\":false}]}}}" \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"inspect-22222222222222222222222222222222","operation":"inspect","value":"accounting.fixture-summary","result":{"ok":true,"runId":"qa-abcdefgh-2","value":{"schema":"qa.evidence/v1","checkId":"accounting.fixture-summary","verdict":"pass","facts":[{"key":"accounts.live-count","actual":2,"expected":2,"pass":true}]}}}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-33333333333333333333333333333333","operation":"bootstrap","value":"identity","error":"QA_ANONYMOUS_BOOTSTRAP_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-44444444444444444444444444444444","operation":"bootstrap","value":"identity","error":"QA_ANONYMOUS_PROVIDER_DISABLED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-55555555555555555555555555555555","operation":"bootstrap","value":"identity","error":"QA_AUTH_RESTORE_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-77777777777777777777777777777777","operation":"bootstrap","value":"identity","error":"QA_BOOTSTRAP_ENTRY_LOAD_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operation":"bootstrap","value":"identity","error":"QA_BOOTSTRAP_ENTRY_SELECTION_LOAD_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","operation":"bootstrap","value":"identity","error":"QA_BOOTSTRAP_ENVIRONMENT_LOAD_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-cccccccccccccccccccccccccccccccc","operation":"bootstrap","value":"identity","error":"QA_BOOTSTRAP_IDENTITY_MODULE_LOAD_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-dddddddddddddddddddddddddddddddd","operation":"bootstrap","value":"identity","error":"QA_BOOTSTRAP_LAUNCH_PLAN_LOAD_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","operation":"bootstrap","value":"identity","error":"QA_BOOTSTRAP_LAUNCH_PLAN_RESOLUTION_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-88888888888888888888888888888888","operation":"bootstrap","value":"identity","error":"QA_FIREBASE_AUTH_CONFIG_REJECTED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-99999999999999999999999999999999","operation":"bootstrap","value":"identity","error":"QA_FIREBASE_AUTH_NETWORK_FAILED"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"dispose-66666666666666666666666666666666","operation":"dispose","value":"identity","error":"QA_AUTH_RESTORE_TIMEOUT"}' \
      'LOG QA RESULT {"schema":"qa.runtime/v1","requestId":"invalid","operation":"launch","value":null,"error":"QA_INVALID_LAUNCH_PLAN"}' \
      "LOG QA FOCUS foo=$RAW_UID" \
      'LOG QA FOCUS visible mode=expense elapsedMs=42 animationMs=148 offset=0' \
      | python3 "$MARKER_FILTER" --allow-golden-marker 'QA FOCUS'
  )" || exit 1

  test "$(printf '%s\n' "$FILTERED_OUTPUT" | wc -l | tr -d ' ')" = 24 || exit 1
  test "$(printf '%s\n' "$FILTERED_OUTPUT" | grep -Fxc 'QA RUNTIME MARKER REJECTED')" = 8 \
    || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA READY ' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq "\"identityHash\":\"$READY_HASH\"" || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA RESULT ' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_ANONYMOUS_BOOTSTRAP_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_ANONYMOUS_PROVIDER_DISABLED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_AUTH_RESTORE_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_AUTH_RESTORE_TIMEOUT' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_BOOTSTRAP_ENTRY_SELECTION_LOAD_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_BOOTSTRAP_ENTRY_LOAD_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_BOOTSTRAP_ENVIRONMENT_LOAD_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_BOOTSTRAP_IDENTITY_MODULE_LOAD_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_BOOTSTRAP_LAUNCH_PLAN_LOAD_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_BOOTSTRAP_LAUNCH_PLAN_RESOLUTION_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_FIREBASE_AUTH_CONFIG_REJECTED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_FIREBASE_AUTH_NETWORK_FAILED' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA_INVALID_LAUNCH_PLAN' || exit 1
  printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA FOCUS visible mode=expense' || exit 1
  if printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq "sha256:$RAW_UID_DIGEST"; then
    exit 1
  fi
  if printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq "$RAW_UID"; then
    exit 1
  fi
  if printf '%s\n' "$FILTERED_OUTPUT" | grep -Eq 'FirebaseError|QA UNKNOWN|unsafe-ready|unsafe-result'; then
    exit 1
  fi
  if printf '%s\n' "$FILTERED_OUTPUT" | grep -Fq 'QA FOCUS foo='; then
    exit 1
  fi

  MARKER_SCAN_ROOT="$(mktemp -d)"
  trap 'rm -rf "$MARKER_SCAN_ROOT"' EXIT INT TERM
  SAFE_SCHEDULE_ID='schedule-alpha'
  SAFE_SCHEDULE_ID_DIGEST="$(printf '%s' "$SAFE_SCHEDULE_ID" | shasum -a 256 | awk '{print $1}')"
  EXPECTED_SCHED_MARKER="$(
    python3 "$MARKER_FILTER" --normalize-expected-marker \
      "QA SCHED backfill scheduleId=$SAFE_SCHEDULE_ID generated=2 fromMs=100 toMs=200"
  )" || exit 1
  ACTUAL_SCHED_MARKER="$(
    printf '%s\n' \
      'LOG QA READY {"schema":"qa.runtime/v1","requestId":"bootstrap-12121212121212121212121212121212","state":"ready","identityMode":"disposable-anonymous","isAnonymous":true,"identityHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
      "LOG QA SCHED backfill scheduleId=$SAFE_SCHEDULE_ID generated=2 fromMs=100 toMs=200" \
      | python3 "$MARKER_FILTER" --allow-golden-marker 'QA SCHED' \
      | tail -n 1
  )" || exit 1
  test "$EXPECTED_SCHED_MARKER" = "$ACTUAL_SCHED_MARKER" || exit 1
  printf '%s\n' "$EXPECTED_SCHED_MARKER" | grep -Fq "sha256:$SAFE_SCHEDULE_ID_DIGEST" || exit 1
  if printf '%s\n' "$EXPECTED_SCHED_MARKER" | grep -Fq "$SAFE_SCHEDULE_ID"; then
    exit 1
  fi
  if python3 "$MARKER_FILTER" --normalize-expected-marker \
    "QA FOCUS visible foo=$RAW_UID" > "$MARKER_SCAN_ROOT/unknown-field"; then
    exit 1
  fi
  test ! -s "$MARKER_SCAN_ROOT/unknown-field" || exit 1

  printf '%s\n' \
    'console.log(`QA BACKUP start identity=session-bound`);' \
    "console.log('QA marker omits uid and userId values');" \
    > "$MARKER_SCAN_ROOT/safe.ts"
  if ! python3 "$MARKER_FILTER" --scan-source "$MARKER_SCAN_ROOT/safe.ts"; then
    exit 1
  fi
  printf '%s\n' \
    'console.log(`QA BACKUP start uid=${user.uid}`);' \
    > "$MARKER_SCAN_ROOT/unsafe.ts"
  if python3 "$MARKER_FILTER" --scan-source "$MARKER_SCAN_ROOT/unsafe.ts"; then
    exit 1
  fi
  printf '%s\n' \
    "console.log('QA BACKUP start', user.uid);" \
    > "$MARKER_SCAN_ROOT/unsafe-separate-arg.ts"
  if python3 "$MARKER_FILTER" --scan-source "$MARKER_SCAN_ROOT/unsafe-separate-arg.ts"; then
    exit 1
  fi
  printf '%s\n' \
    "console.log('uid=', actualUid);" \
    > "$MARKER_SCAN_ROOT/unsafe-actual-uid.ts"
  if python3 "$MARKER_FILTER" --scan-source "$MARKER_SCAN_ROOT/unsafe-actual-uid.ts"; then
    exit 1
  fi
  printf '%s\n' \
    "const marker = 'QA BACKUP start'; console.log(marker, user.uid);" \
    > "$MARKER_SCAN_ROOT/unsafe-variable-marker.ts"
  if python3 "$MARKER_FILTER" --scan-source "$MARKER_SCAN_ROOT/unsafe-variable-marker.ts"; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL disk 前 marker filter 必須丟棄 raw UID 與非 allowlist output"
fi

NATIVE_DIAGNOSTIC_OUTPUT="$(
  printf '%s\n' \
    'prefix QA NATIVE FIREBASE_CONFIG_VALID' \
    'QA NATIVE BUNDLE_INDEX_QA_LOCALHOST' \
    'QA NATIVE UNKNOWN_SECRET value=hidden' \
    'QA NATIVE REACT_START_RETURNED QA READY {}' \
    | python3 "$MARKER_FILTER"
)"
if [ "$(printf '%s\n' "$NATIVE_DIAGNOSTIC_OUTPUT" | grep -Fxc 'QA NATIVE FIREBASE_CONFIG_VALID')" = 1 ] \
  && [ "$(printf '%s\n' "$NATIVE_DIAGNOSTIC_OUTPUT" | grep -Fxc 'QA NATIVE BUNDLE_INDEX_QA_LOCALHOST')" = 1 ] \
  && [ "$(printf '%s\n' "$NATIVE_DIAGNOSTIC_OUTPUT" | grep -Fxc 'QA RUNTIME MARKER REJECTED')" = 2 ] \
  && ! printf '%s\n' "$NATIVE_DIAGNOSTIC_OUTPUT" | grep -Fq 'hidden'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL native diagnostic 必須 exact allowlist 且混合 marker fail-closed"
fi

if (
  set -e
  RAW_UID='preReadyRawQaUser1234567890'
  READY_HASH="$(printf '%s' "$RAW_UID" | shasum -a 256 | awk '{print $1}')"
  PRE_READY_OUTPUT="$(
    printf '%s\n' \
      "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"inspect-10101010101010101010101010101010\",\"operation\":\"inspect\",\"value\":\"accounting.fixture-summary\",\"result\":{\"ok\":true,\"runId\":\"qa-abcdefgh-2\",\"value\":{\"schema\":\"qa.evidence/v1\",\"checkId\":\"accounting.fixture-summary\",\"verdict\":\"pass\",\"facts\":[{\"key\":\"accounts.signature\",\"actual\":\"$RAW_UID\",\"expected\":\"safe-reference\",\"pass\":false}]}}}" \
      "QA SCHED backfill scheduleId=$RAW_UID generated=2 fromMs=100 toMs=200" \
      'QA RESULT {"schema":"qa.runtime/v1","requestId":"prepare-20202020202020202020202020202020","operation":"prepare","value":"r02_end","result":{"ok":true,"runId":"qa-abcdefgh-2","value":{"sceneId":"r02_end","fingerprint":"r02_end:a3:c7:t9:f0:s0:v1"}}}' \
      'QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-30303030303030303030303030303030","operation":"bootstrap","value":"identity","error":"QA_ANONYMOUS_BOOTSTRAP_FAILED"}' \
      'QA RESULT {"schema":"qa.runtime/v1","requestId":"dispose-40404040404040404040404040404040","operation":"dispose","value":"identity","error":"QA_AUTH_RESTORE_TIMEOUT"}' \
      'QA RESULT {"schema":"qa.runtime/v1","requestId":"invalid","operation":"launch","value":null,"error":"QA_INVALID_LAUNCH_PLAN"}' \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-50505050505050505050505050505050\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"}" \
      | python3 "$MARKER_FILTER" --allow-golden-marker 'QA SCHED'
  )" || exit 1

  test "$(printf '%s\n' "$PRE_READY_OUTPUT" | grep -Fxc 'QA RUNTIME MARKER REJECTED')" = 3 \
    || exit 1
  test "$(printf '%s\n' "$PRE_READY_OUTPUT" | grep -Fc 'QA RESULT ')" = 3 \
    || exit 1
  test "$(printf '%s\n' "$PRE_READY_OUTPUT" | grep -Fc 'QA READY ')" = 1 \
    || exit 1
  printf '%s\n' "$PRE_READY_OUTPUT" | grep -Fq 'QA_ANONYMOUS_BOOTSTRAP_FAILED' || exit 1
  printf '%s\n' "$PRE_READY_OUTPUT" | grep -Fq 'QA_AUTH_RESTORE_TIMEOUT' || exit 1
  printf '%s\n' "$PRE_READY_OUTPUT" | grep -Fq 'QA_INVALID_LAUNCH_PLAN' || exit 1
  if printf '%s\n' "$PRE_READY_OUTPUT" \
    | grep -vF 'QA READY ' \
    | grep -Eq -- "$RAW_UID|$READY_HASH|sha256:$READY_HASH|QA SCHED"; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL 第一筆 valid READY 前不得持久化成功 RESULT 或 selected golden marker"
fi

if (
  set -e
  RAW_UID='rawQaUser1234567890abcdef'
  READY_HASH="$(printf '%s' "$RAW_UID" | shasum -a 256 | awk '{print $1}')"
  FILTERED_IDENTITY_COLLISION_OUTPUT="$(
    printf '%s\n' \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"}" \
      "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"inspect-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"operation\":\"inspect\",\"value\":\"accounting.fixture-summary\",\"result\":{\"ok\":true,\"runId\":\"qa-abcdefgh-2\",\"value\":{\"schema\":\"qa.evidence/v1\",\"checkId\":\"accounting.fixture-summary\",\"verdict\":\"pass\",\"facts\":[{\"key\":\"accounts.signature\",\"actual\":\"$RAW_UID\",\"expected\":\"safe-reference\",\"pass\":false}]}}}" \
      "QA SCHED backfill scheduleId=$RAW_UID generated=2 fromMs=100 toMs=200" \
      'QA READY {"schema":"qa.runtime/v1","requestId":"open-app-cccccccccccccccccccccccccccccccc","state":"ready","identityMode":"disposable-anonymous","isAnonymous":true,"identityHash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}' \
      | python3 "$MARKER_FILTER" --allow-golden-marker 'QA SCHED'
  )" || exit 1

  test "$(printf '%s\n' "$FILTERED_IDENTITY_COLLISION_OUTPUT" | grep -Fxc 'QA RUNTIME MARKER REJECTED')" = 3 \
    || exit 1
  test "$(printf '%s\n' "$FILTERED_IDENTITY_COLLISION_OUTPUT" | grep -Fc 'QA READY ')" = 1 \
    || exit 1
  if printf '%s\n' "$FILTERED_IDENTITY_COLLISION_OUTPUT" \
    | grep -vF 'QA READY ' \
    | grep -Eq -- "$RAW_UID|$READY_HASH|sha256:$READY_HASH"; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL READY identityHash digest 不得從 RESULT 或 golden marker 持久化"
fi

if (
  set -e
  RAW_UID='rawQaUser1234567890abcdef'
  VALID_DISPOSE_REQUEST='dispose-77777777777777777777777777777777'
  READY_HASH='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  FILTERED_REJECTION_OUTPUT="$(
    printf '%s\n' \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-00000000000000000000000000000000\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"}" \
      "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$VALID_DISPOSE_REQUEST\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}" \
      "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$VALID_DISPOSE_REQUEST\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}},\"uid\":\"$RAW_UID\"}" \
      'QA RESULT {"schema":"qa.runtime/v1","requestId":"bootstrap-88888888888888888888888888888888","operation":"bootstrap","value":"identity","error":"QA_ANONYMOUS_BOOTSTRAP_FAILED"}' \
      "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-99999999999999999999999999999999\",\"operation\":\"bootstrap\",\"value\":\"identity\",\"error\":\"$RAW_UID\"}" \
      | python3 "$MARKER_FILTER"
  )"

  test "$(printf '%s\n' "$FILTERED_REJECTION_OUTPUT" | grep -Fxc 'QA RUNTIME MARKER REJECTED')" = 2 \
    || exit 1
  printf '%s\n' "$FILTERED_REJECTION_OUTPUT" \
    | grep -Fq "\"requestId\":\"$VALID_DISPOSE_REQUEST\"" \
    || exit 1
  printf '%s\n' "$FILTERED_REJECTION_OUTPUT" \
    | grep -Fq 'QA_ANONYMOUS_BOOTSTRAP_FAILED' \
    || exit 1
  if printf '%s\n' "$FILTERED_REJECTION_OUTPUT" | grep -Fq "$RAW_UID"; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL malformed runtime marker 必須輸出固定 rejection sentinel"
fi

if (
  set -e
  RAW_UID='rawQaUser1234567890abcdef'
  READY_HASH='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  MIXED_RUNTIME_OUTPUT="$(
    printf '%s\n' \
      "QA RESULT {\"uid\":\"$RAW_UID\"} QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"}" \
      "QA READY {\"schema\":\"qa.runtime/v1\",\"requestId\":\"bootstrap-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"state\":\"ready\",\"identityMode\":\"disposable-anonymous\",\"isAnonymous\":true,\"identityHash\":\"$READY_HASH\"} QA READY {\"schema\":\"qa.runtime/v1\"}" \
      | python3 "$MARKER_FILTER"
  )"

  test "$(printf '%s\n' "$MIXED_RUNTIME_OUTPUT" | grep -Fxc 'QA RUNTIME MARKER REJECTED')" = 2 \
    || exit 1
  if printf '%s\n' "$MIXED_RUNTIME_OUTPUT" \
    | grep -Eq -- "$RAW_UID|$READY_HASH|QA READY |QA RESULT "; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL 單一實體行只能含一個 runtime marker prefix"
fi

READY_LOG_CLEANUP_CALLS="$(grep -Fc 'rm -f "$READY_MARKER_LOG"' "$SIM_REVIEW" || true)"
if [ "$READY_LOG_CLEANUP_CALLS" -ge 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL normal 與 trap cleanup 都必須刪 transient READY marker log"
fi

APP_CONSOLE_LAUNCH_COUNT="$(grep -Fh -- 'qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN"' \
  "$SIM_REVIEW" "$RUNTIME" | wc -l | tr -d ' ')"
if [ "$APP_CONSOLE_LAUNCH_COUNT" -ge 4 ] \
  && grep -Fq 'SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN="$qa_session_token"' "$RUNTIME"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL bootstrap、operation、manual-only 與 disposal 都必須經 console helper 注入同一 session token"
fi

echo "=== Disposable identity teardown ==="
has_literal "dispose validator actual definition" "$SIM_REVIEW" 'run_and_validate_qa_identity_disposal() {'
has_literal "dispose validator unique request" "$SIM_REVIEW" 'DISPOSE_REQUEST_ID="dispose-$(openssl rand -hex 16)"'
has_literal "dispose validator log offset" "$SIM_REVIEW" 'DISPOSE_LOG_OFFSET="$(wc -l < "$READY_MARKER_LOG")"'
has_literal "dispose validator 120s deadline" "$SIM_REVIEW" 'DISPOSE_DEADLINE=$((SECONDS + 120))'
has_literal "dispose validator exact-one related" "$SIM_REVIEW" '[ "$dispose_related_count" -eq 1 ]'
has_literal "dispose validator exact success" "$SIM_REVIEW" '[ "$dispose_exact_count" -eq 1 ]'
has_literal "dispose validator timeout safe code" "$SIM_REVIEW" 'QA_IDENTITY_DISPOSAL_RESULT_TIMEOUT'
has_literal "dispose validator 實際拒 sentinel" "$SIM_REVIEW" 'if ! require_runtime_marker_window_clean "$dispose_log_window"; then'
has_literal "dispose validator candidate 後 terminate" "$SIM_REVIEW" 'xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true'
has_literal "dispose validator candidate 後 quiet" "$SIM_REVIEW" 'if ! wait_for_runtime_marker_quiet_window "$DISPOSE_LOG_OFFSET"; then'

DISPOSAL_VALIDATE_BLOCK="$(sed -n '/^run_and_validate_qa_identity_disposal() {$/,/^}$/p' "$SIM_REVIEW")"
RUNTIME_WINDOW_VALIDATE_BLOCK="$(sed -n '/^require_runtime_marker_window_clean() {$/,/^}$/p' "$SIM_REVIEW")"
RUNTIME_SESSION_VALIDATE_BLOCK="$(sed -n '/^require_runtime_marker_session_clean() {$/,/^}$/p' "$SIM_REVIEW")"
RUNTIME_QUIET_BLOCK="$(sed -n '/^wait_for_runtime_marker_quiet_window() {$/,/^}$/p' "$SIM_REVIEW")"
if (
  set -e
  test -n "$DISPOSAL_VALIDATE_BLOCK"
  test -n "$RUNTIME_WINDOW_VALIDATE_BLOCK"
  test -n "$RUNTIME_SESSION_VALIDATE_BLOCK"
  test -n "$RUNTIME_QUIET_BLOCK"
  DISPOSAL_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$DISPOSAL_TEST_ROOT"' EXIT INT TERM
  READY_MARKER_LOG="$DISPOSAL_TEST_ROOT/markers.log"
  QA_BUNDLE_ID='com.example.qa'
  QA_SESSION_TOKEN='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  READY_IDENTITY_HASH='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  QA_FIREBASE_PROJECT_ID='susugigi-qa'
  CONTROL_PLANE_ROOT="$DISPOSAL_TEST_ROOT/control"
  SESSION_CONTROL_PLANE_ROOT="$CONTROL_PLANE_ROOT"
  QUALITY_ROOT="$DISPOSAL_TEST_ROOT/quality"
  SESSION_QUALITY_ROOT="$QUALITY_ROOT"
  IDENTITY_TEARDOWN_POSSIBLE=1
  SESSION_FAILED=0
  METRO_FILTER_PID=''
  RUNTIME_MARKER_SESSION_TAINTED=0
  RUNTIME_MARKER_SESSION_START_OFFSET=0
  DISPOSAL_MODE=success
  LAST_DISPOSE_REQUEST_ID=''
  LAUNCH_COUNT=0
  DELAYED_WRITER_PID=''

  xcrun() {
    test "$1" = simctl
    if [ "$2" = terminate ]; then
      return 0
    fi
    test "$2" = launch
    test "$3" = booted
    test "$4" = "$QA_BUNDLE_ID"
    test "$5" = --qa-request-id
    [[ "$6" =~ ^dispose-[0-9a-f]{32}$ ]]
    test "${SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN:-}" = "$QA_SESSION_TOKEN"
    test "$7" = --qa-dispose-identity
    test "$8" = true
    if [ -n "$LAST_DISPOSE_REQUEST_ID" ]; then
      test "$6" != "$LAST_DISPOSE_REQUEST_ID"
    fi
    LAST_DISPOSE_REQUEST_ID="$6"
    LAUNCH_COUNT=$((LAUNCH_COUNT + 1))
    case "$DISPOSAL_MODE" in
      success)
        printf '%s\n' "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}" >> "$READY_MARKER_LOG"
        ;;
      duplicate)
        printf '%s\n' \
          "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}" \
          "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}" >> "$READY_MARKER_LOG"
        ;;
      error)
        printf '%s\n' "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"error\":\"QA_IDENTITY_DELETE_FAILED\"}" >> "$READY_MARKER_LOG"
        ;;
      unsafe-duplicate)
        printf '%s\n' \
          "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}" \
          "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}},\"uid\":\"rawQaUser1234567890abcdef\"}" \
          | python3 "$MARKER_FILTER" >> "$READY_MARKER_LOG"
        ;;
      delayed-unsafe-duplicate)
        (
          printf '%s\n' \
            "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}" \
            | python3 "$MARKER_FILTER" >> "$READY_MARKER_LOG"
          sleep 0.8
          printf '%s\n' \
            "QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$6\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}},\"uid\":\"rawQaUser1234567890abcdef\"}" \
            | python3 "$MARKER_FILTER" >> "$READY_MARKER_LOG"
        ) &
        DELAYED_WRITER_PID=$!
        ;;
    esac
  }

  python3() {
    if [ "$1" = "$QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py" ]; then
      test "$2" = --project
      test "$3" = "$QA_FIREBASE_PROJECT_ID"
      read -r identity_hash
      test "$identity_hash" = "$READY_IDENTITY_HASH"
      printf '%s\n' QA_AUTH_IDENTITY_ABSENT
      return 0
    fi
    command python3 "$@"
  }

  require_marker_filter_running() { return 0; }
  stop_qa_app_console_capture_with_deadline() { return 0; }
  qa_launch_app_with_marker_stream() {
    local session_token="$1"
    shift
    SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN="$session_token" \
      xcrun simctl launch booted "$QA_BUNDLE_ID" "$@"
  }
  qa_runtime_capture_disposal_identity() { printf '%s' "$READY_IDENTITY_HASH"; }
  require_session_runtime_snapshots_current() { return 0; }
  run_session_snapshot_command() {
    test "$1" = /usr/bin/python3 && test "$2" = -I || return 1
    shift 2
    python3 "$@"
  }

  eval "$RUNTIME_QUIET_BLOCK"
  eval "$RUNTIME_SESSION_VALIDATE_BLOCK"
  eval "$RUNTIME_WINDOW_VALIDATE_BLOCK"
  eval "$DISPOSAL_VALIDATE_BLOCK"
  : > "$READY_MARKER_LOG"
  run_and_validate_qa_identity_disposal > "$DISPOSAL_TEST_ROOT/stdout" 2> "$DISPOSAL_TEST_ROOT/stderr"
  test "$LAUNCH_COUNT" = 1
  test "$IDENTITY_TEARDOWN_POSSIBLE" = 1
  if grep -Fq "$QA_SESSION_TOKEN" "$DISPOSAL_TEST_ROOT/stdout" "$DISPOSAL_TEST_ROOT/stderr"; then
    exit 1
  fi

  : > "$READY_MARKER_LOG"
  DISPOSAL_MODE=duplicate
  if run_and_validate_qa_identity_disposal > "$DISPOSAL_TEST_ROOT/stdout" 2> "$DISPOSAL_TEST_ROOT/stderr"; then
    exit 1
  fi
  test "$IDENTITY_TEARDOWN_POSSIBLE" = 1

  : > "$READY_MARKER_LOG"
  DISPOSAL_MODE=error
  if run_and_validate_qa_identity_disposal > "$DISPOSAL_TEST_ROOT/stdout" 2> "$DISPOSAL_TEST_ROOT/stderr"; then
    exit 1
  fi
  test "$IDENTITY_TEARDOWN_POSSIBLE" = 1

  : > "$READY_MARKER_LOG"
  DISPOSAL_MODE=unsafe-duplicate
  if run_and_validate_qa_identity_disposal > "$DISPOSAL_TEST_ROOT/stdout" 2> "$DISPOSAL_TEST_ROOT/stderr"; then
    exit 1
  fi
  test "$IDENTITY_TEARDOWN_POSSIBLE" = 1
  if grep -Fq 'rawQaUser1234567890abcdef' \
    "$READY_MARKER_LOG" "$DISPOSAL_TEST_ROOT/stdout" "$DISPOSAL_TEST_ROOT/stderr"; then
    exit 1
  fi

  : > "$READY_MARKER_LOG"
  RUNTIME_MARKER_SESSION_TAINTED=0
  SESSION_FAILED=0
  DISPOSAL_MODE=delayed-unsafe-duplicate
  set +e
  run_and_validate_qa_identity_disposal > "$DISPOSAL_TEST_ROOT/stdout" 2> "$DISPOSAL_TEST_ROOT/stderr"
  DELAYED_DISPOSAL_STATUS=$?
  set -e
  wait "$DELAYED_WRITER_PID"
  test "$DELAYED_DISPOSAL_STATUS" -ne 0 || exit 1
  test "$RUNTIME_MARKER_SESSION_TAINTED" = 1 || exit 1
  test "$SESSION_FAILED" = 1 || exit 1
  if grep -Fq 'rawQaUser1234567890abcdef' \
    "$READY_MARKER_LOG" "$DISPOSAL_TEST_ROOT/stdout" "$DISPOSAL_TEST_ROOT/stderr"; then
    exit 1
  fi

  : > "$READY_MARKER_LOG"
  if require_runtime_marker_session_clean 2>/dev/null; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL actual disposal validator 動態契約"
fi

for skill in "$GAME_TEST" "$SIM_REVIEW"; do
  has_literal "dispose operation" "$skill" 'dispose RESULT operation 必須為 `dispose`。'
  has_literal "dispose value" "$skill" 'dispose RESULT value 必須為 `identity`。'
  has_literal "dispose anonymous mode" "$skill" 'dispose RESULT identityMode 必須為 `disposable-anonymous`。'
  has_literal "dispose auth deleted" "$skill" 'dispose RESULT authDeleted 必須為 `true`。'
  has_literal "dispose 不得含 uid" "$skill" 'dispose RESULT 不得包含 `uid`。'
  has_literal "dispose fail closed" "$skill" 'dispose 失敗時整體結果判定 `fail`。'
done
has_literal "sim-review dispose QA only" "$SIM_REVIEW" 'dispose launch 只允許 QA build。'
has_literal "sim-review dispose flag" "$SIM_REVIEW" '--qa-dispose-identity true'
has_literal "sim-review dispose 同 requestId" "$SIM_REVIEW" 'dispose RESULT requestId 必須等於 `DISPOSE_REQUEST_ID`。'
has_literal "dispose launch requestId" "$SIM_REVIEW" '    --qa-request-id "$DISPOSE_REQUEST_ID" \'
has_literal "dispose launch QA-only flag" "$SIM_REVIEW" '    --qa-dispose-identity true'
has_literal "teardown 預設不啟用" "$SIM_REVIEW" 'IDENTITY_TEARDOWN_POSSIBLE=0'
has_literal "teardown launch 前啟用" "$RUNTIME" 'IDENTITY_TEARDOWN_POSSIBLE=1'
has_literal "teardown READY 後確認" "$RUNTIME" 'IDENTITY_TEARDOWN_CONFIRMED=1'
has_literal "teardown 未啟用不執行" "$SIM_REVIEW" '[ "$IDENTITY_TEARDOWN_POSSIBLE" = 1 ] || return 0'
has_literal "teardown 防重入" "$SIM_REVIEW" 'IDENTITY_TEARDOWN_RUNNING=1'
has_literal "teardown 防重複" "$SIM_REVIEW" 'IDENTITY_TEARDOWN_ATTEMPTED=1'
has_literal "teardown 失敗保留 session fail" "$SIM_REVIEW" 'SESSION_FAILED=1'
has_literal "teardown 失敗明示帳號未清除" "$SIM_REVIEW" 'QA anonymous account cleanup failed; account not cleaned or proven absent'
has_literal "cleanup 防重入" "$SIM_REVIEW" 'SIM_REVIEW_CLEANUP_RUNNING=1'
has_literal "EXIT trap 保留原狀態" "$SIM_REVIEW" 'trap '\''finalize_sim_review "$?"'\'' EXIT'
lacks_pattern "不得以 simulator erase 取代 disposal" "$SIM_REVIEW" 'simctl[[:space:]]+erase'

TEARDOWN_CALL_COUNT="$(grep -Fc 'if ! dispose_qa_identity_if_required; then' "$SIM_REVIEW" || true)"
if [ "$TEARDOWN_CALL_COUNT" -ge 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL 正常與 cleanup 路徑都必須呼叫 identity teardown"
fi

TEARDOWN_ARM_COUNT="$(grep -Fh 'IDENTITY_TEARDOWN_POSSIBLE=1' \
  "$SIM_REVIEW" "$RUNTIME" | wc -l | tr -d ' ')"
if [ "$TEARDOWN_ARM_COUNT" -ge 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL bootstrap 與 operation launch 前都必須取得 teardown 責任"
fi

has_literal "bootstrap launch 前取得 teardown 責任" "$RUNTIME" 'IDENTITY_TEARDOWN_POSSIBLE=1'

echo "=== Installed Firebase identity ==="
lacks_pattern "QA build 不得自動 launch" "$SIM_REVIEW" 'react-native[[:space:]]+run-ios'
has_literal "QA build 使用 xcodebuild" "$SIM_REVIEW" 'xcodebuild \'
has_literal "QA build 使用 simulator install" "$SIM_REVIEW" 'xcrun simctl install booted "$QA_APP_ARTIFACT"'
has_literal "build artifact 路徑" "$SIM_REVIEW" 'QA_APP_ARTIFACT="$QA_TARGET_BUILD_DIR/$QA_WRAPPER_NAME"'
has_literal "build artifact Firebase identity" "$SIM_REVIEW" '--qa-plist "$QA_APP_ARTIFACT/GoogleService-Info.plist"'
has_literal "build artifact plist 逐字一致" "$SIM_REVIEW" 'cmp -s "$QA_FIREBASE_SOURCE" "$QA_APP_ARTIFACT/GoogleService-Info.plist"'
has_literal "QA URL route allowlist" "$SIM_REVIEW" 'QA_ALLOWED_URL_SCHEME="$QA_BUNDLE_ID"'
has_literal "Production OAuth route denylist" "$SIM_REVIEW" 'QA_PRODUCTION_URL_SCHEME="com.googleusercontent.apps.515173750154-4fftspgi257ovtom1cf3hrdbaslpr3km"'
has_literal "QA URL route identity probe" "$SIM_REVIEW" 'plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw -o - "$qa_info_plist"'
has_literal "QA URL route 禁第二 scheme" "$SIM_REVIEW" 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:1'
has_literal "QA URL route 禁第二 type" "$SIM_REVIEW" 'Print :CFBundleURLTypes:1'
has_literal "AppDelegate source 路徑" "$SIM_REVIEW" 'QA_APP_DELEGATE_SOURCE="$MAIN_REPO/ios/SuSuGiGiApp/AppDelegate.swift"'
has_literal "AppDelegate compile guard" "$SIM_REVIEW" 'verify_qa_app_delegate_compile_guard "$QA_APP_DELEGATE_SOURCE"'
has_literal "AppDelegate 排除 Production handler" "$SIM_REVIEW" 'QA target 的 AppDelegate source 必須以 `#if !QA` 排除 Production GoogleSignIn import 與 URL handler。'
has_literal "不得用整顆 executable 判 SDK" "$SIM_REVIEW" '不得以整顆 QA executable 是否連入 GIDSignIn SDK 作隔離判定。'
lacks_pattern "不得以 nm 掃整顆 QA executable" "$SIM_REVIEW" 'nm[[:space:]]+-u.*GIDSignIn'
has_literal "QA compilation condition" "$SIM_REVIEW" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS'
has_literal "built artifact URL isolation" "$SIM_REVIEW" 'verify_qa_artifact_url_isolation "$QA_APP_ARTIFACT"'
has_literal "installed artifact URL isolation" "$SIM_REVIEW" 'verify_qa_artifact_url_isolation "$QA_APP_CONTAINER"'
has_literal "resolver 取得 payload app id" "$SIM_REVIEW" 'QA_GOOGLE_APP_ID 取自 `qaGoogleAppId`。'
has_literal "resolver 帶 app id" "$SIM_REVIEW" '--qa-google-app-id "$QA_GOOGLE_APP_ID"'
has_literal "resolver 取得 payload config digest" "$SIM_REVIEW" 'QA_FIREBASE_CONFIG_SHA256 取自 `qaFirebaseConfigSha256`。'
has_literal "resolver 帶 config digest" "$SIM_REVIEW" '--qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256"'
has_literal "來源 config digest 對 payload" "$SIM_REVIEW" 'test "$SOURCE_QA_FIREBASE_CONFIG_SHA256" = "$QA_FIREBASE_CONFIG_SHA256"'
has_literal "安裝產物逐字一致" "$SIM_REVIEW" 'cmp -s "$QA_FIREBASE_SOURCE" "$QA_APP_CONTAINER/GoogleService-Info.plist"'
has_literal "不得輸出 API key" "$SIM_REVIEW" '不得輸出 `API_KEY`。'

SIM_DIGEST_FLAG_COUNT="$(grep -Fc -- '--qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256"' "$SIM_REVIEW" || true)"
if [ "$SIM_DIGEST_FLAG_COUNT" -ge 3 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL source main 與 installed resolver 都必須帶 config digest"
fi

SOURCE_GUARD_LINE="$(grep -nF 'verify_qa_app_delegate_compile_guard "$QA_APP_DELEGATE_SOURCE"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
BUILD_LINE="$(grep -nF 'xcodebuild \' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
BUILT_IDENTITY_LINE="$(grep -nF -- '--qa-plist "$QA_APP_ARTIFACT/GoogleService-Info.plist"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
BUILT_OAUTH_LINE="$(grep -nF 'verify_qa_artifact_url_isolation "$QA_APP_ARTIFACT"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
INSTALL_LINE="$(grep -nF 'xcrun simctl install booted "$QA_APP_ARTIFACT"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
INSTALLED_IDENTITY_LINE="$(grep -nF -- '--qa-plist "$QA_APP_CONTAINER/GoogleService-Info.plist"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
INSTALLED_OAUTH_LINE="$(grep -nF 'verify_qa_artifact_url_isolation "$QA_APP_CONTAINER"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
if [ -n "$SOURCE_GUARD_LINE" ] \
  && [ -n "$BUILD_LINE" ] \
  && [ -n "$BUILT_IDENTITY_LINE" ] \
  && [ -n "$BUILT_OAUTH_LINE" ] \
  && [ -n "$INSTALL_LINE" ] \
  && [ -n "$INSTALLED_IDENTITY_LINE" ] \
  && [ -n "$INSTALLED_OAUTH_LINE" ] \
  && [ "$SOURCE_GUARD_LINE" -lt "$BUILD_LINE" ] \
  && [ "$BUILD_LINE" -lt "$BUILT_IDENTITY_LINE" ] \
  && [ "$BUILT_IDENTITY_LINE" -lt "$BUILT_OAUTH_LINE" ] \
  && [ "$BUILT_OAUTH_LINE" -lt "$INSTALL_LINE" ] \
  && [ "$INSTALL_LINE" -lt "$INSTALLED_IDENTITY_LINE" ] \
  && [ "$INSTALLED_IDENTITY_LINE" -lt "$INSTALLED_OAUTH_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL build、artifact identity、install、installed identity 次序"
fi

BOOTSTRAP_SECTION="$(sed -n '/^run_and_validate_qa_bootstrap() {/,/^}/p' "$RUNTIME")"
if printf '%s\n' "$BOOTSTRAP_SECTION" | grep -Fq -- 'qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN"' \
  && printf '%s\n' "$BOOTSTRAP_SECTION" | grep -Fq -- '--qa-request-id "$BOOTSTRAP_REQUEST_ID"' \
  && ! printf '%s\n' "$BOOTSTRAP_SECTION" | grep -Eq -- '--qa-(session-token|prepare|inspect|dispose-identity)'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL 安裝後第一次 launch 必須是 token-bound 身分 bootstrap"
fi

echo "=== Private QA plist lifecycle ==="
has_literal "來源鎖定 Impl target" "$SIM_REVIEW" 'QA_FIREBASE_SOURCE="$IMPL_WORKTREE/ios/GoogleService-Info-QA.plist"'
has_literal "來源 QA plist 拒 symlink" "$SIM_REVIEW" 'test ! -L "$QA_FIREBASE_SOURCE"'
has_literal "main 臨時私密路徑" "$SIM_REVIEW" 'MAIN_QA_FIREBASE_CONFIG="$MAIN_REPO/ios/GoogleService-Info-QA.plist"'
has_literal "feature ignore 生效" "$SIM_REVIEW" 'git -C "$MAIN_REPO" check-ignore -q "ios/GoogleService-Info-QA.plist"'
has_literal "私密檔才複製" "$SIM_REVIEW" 'install -m 600 "$QA_FIREBASE_SOURCE" "$MAIN_QA_FIREBASE_CONFIG"'
has_literal "複製前預約清除所有權" "$SIM_REVIEW" 'MAIN_QA_FIREBASE_CREATED=1'
has_literal "錯誤 trap 呼叫安全 cleanup" "$SIM_REVIEW" 'if ! cleanup_sim_review; then'
has_literal "trap 只刪本次建立副本" "$SIM_REVIEW" 'if ! remove_main_qa_firebase_config; then'
has_literal "清除 main 私密副本" "$SIM_REVIEW" 'rm -f "$MAIN_QA_FIREBASE_CONFIG"'
has_literal "dangling symlink 也視為存在" "$SIM_REVIEW" 'test ! -L "$MAIN_QA_FIREBASE_CONFIG"'
has_literal "刪除後驗一般路徑不存在" "$SIM_REVIEW" '[ ! -e "$MAIN_QA_FIREBASE_CONFIG" ]'
has_literal "刪除後驗 symlink 不存在" "$SIM_REVIEW" '[ ! -L "$MAIN_QA_FIREBASE_CONFIG" ]'
has_literal "刪除失敗固定安全錯誤" "$SIM_REVIEW" 'QA_FIREBASE_PRIVATE_COPY_CLEANUP_FAILED'
has_literal "刪除失敗保留 ownership" "$SIM_REVIEW" '`MAIN_QA_FIREBASE_CREATED` 保持 `1`。'
has_literal "刪除失敗阻止還原" "$SIM_REVIEW" 'QA 私密副本 cleanup 失敗時不得 checkout main。'
has_literal "不得讀 Production plist" "$SIM_REVIEW" '不得讀取或複製 Production plist。'

QA_ABSENT_LINE="$(grep -nF 'test ! -e "$MAIN_QA_FIREBASE_CONFIG"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
QA_OWNERSHIP_LINE="$(grep -nF 'MAIN_QA_FIREBASE_CREATED=1' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
QA_INSTALL_LINE="$(grep -nF 'install -m 600 "$QA_FIREBASE_SOURCE" "$MAIN_QA_FIREBASE_CONFIG"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
if [ -n "$QA_ABSENT_LINE" ] \
  && [ -n "$QA_OWNERSHIP_LINE" ] \
  && [ -n "$QA_INSTALL_LINE" ] \
  && [ "$QA_ABSENT_LINE" -lt "$QA_OWNERSHIP_LINE" ] \
  && [ "$QA_OWNERSHIP_LINE" -lt "$QA_INSTALL_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL QA plist 必須在確認不存在後、install 前預約 cleanup"
fi

QA_PLIST_REMOVE_BLOCK="$(sed -n '/^remove_main_qa_firebase_config() {$/,/^}$/p' "$SIM_REVIEW")"
CLEANUP_RM_LINE="$(printf '%s\n' "$QA_PLIST_REMOVE_BLOCK" | grep -nF 'rm -f "$MAIN_QA_FIREBASE_CONFIG"' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_ABSENT_LINE="$(printf '%s\n' "$QA_PLIST_REMOVE_BLOCK" | grep -nF '[ ! -e "$MAIN_QA_FIREBASE_CONFIG" ]' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_NOT_LINK_LINE="$(printf '%s\n' "$QA_PLIST_REMOVE_BLOCK" | grep -nF '[ ! -L "$MAIN_QA_FIREBASE_CONFIG" ]' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_CLEAR_LINE="$(printf '%s\n' "$QA_PLIST_REMOVE_BLOCK" | grep -nF 'MAIN_QA_FIREBASE_CREATED=0' | head -n 1 | cut -d: -f1 || true)"
if [ -n "$CLEANUP_RM_LINE" ] \
  && [ -n "$CLEANUP_ABSENT_LINE" ] \
  && [ -n "$CLEANUP_NOT_LINK_LINE" ] \
  && [ -n "$CLEANUP_CLEAR_LINE" ] \
  && [ "$CLEANUP_RM_LINE" -lt "$CLEANUP_ABSENT_LINE" ] \
  && [ "$CLEANUP_ABSENT_LINE" -lt "$CLEANUP_CLEAR_LINE" ] \
  && [ "$CLEANUP_NOT_LINK_LINE" -lt "$CLEANUP_CLEAR_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL QA plist ownership 只可在刪除並驗證路徑消失後清除"
fi

QA_PLIST_REMOVE_CALLS="$(grep -Fc 'if ! remove_main_qa_firebase_config; then' "$SIM_REVIEW" || true)"
if [ "$QA_PLIST_REMOVE_CALLS" -ge 3 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL trap、安裝後與正常還原都必須走 QA plist 安全清理"
fi

QA_ABSENT_BLOCK="$(awk '
  /^test ! -e "\$MAIN_QA_FIREBASE_CONFIG"$/ {
    print
    if ((getline next_line) > 0) print next_line
    exit
  }
' "$SIM_REVIEW")"
if (
  set -e
  QA_ABSENT_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$QA_ABSENT_TEST_ROOT"' EXIT INT TERM
  MAIN_QA_FIREBASE_CONFIG="$QA_ABSENT_TEST_ROOT/GoogleService-Info-QA.plist"
  ln -s "$QA_ABSENT_TEST_ROOT/missing.plist" "$MAIN_QA_FIREBASE_CONFIG"
  if eval "$QA_ABSENT_BLOCK"; then
    exit 1
  fi
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL dangling QA plist symlink 必須被 absent gate 阻斷"
fi

echo "=== Detached main cleanup ==="
has_literal "初始化 main repo 狀態" "$SIM_REVIEW" 'MAIN_REPO=""'
has_literal "初始化 detached 狀態" "$SIM_REVIEW" 'MAIN_DETACHED=0'
has_literal "初始化 restore responsibility" "$SIM_REVIEW" 'MAIN_RESTORE_REQUIRED=0'
has_literal "記錄 main 起始 HEAD" "$SIM_REVIEW" 'MAIN_START_HEAD=""'
has_literal "cleanup 依實際 branch" "$SIM_REVIEW" 'MAIN_ACTUAL_BRANCH="$(/usr/bin/git -C "$MAIN_REPO" branch --show-current)"'
has_literal "cleanup 依實際 HEAD" "$SIM_REVIEW" 'MAIN_ACTUAL_HEAD="$(/usr/bin/git -C "$MAIN_REPO" rev-parse HEAD)"'
has_adjacent_lines "detached checkout 後取得還原責任" "$SIM_REVIEW" \
  '/usr/bin/git -C "$MAIN_REPO" checkout --detach "$TARGET_COMMIT"' \
  'MAIN_DETACHED=1'
has_literal "cleanup 僅處理本次 restore responsibility" "$SIM_REVIEW" 'if [ "$MAIN_RESTORE_REQUIRED" = 1 ] && [ -n "$MAIN_REPO" ]; then'
has_literal "初始化 restore blocked" "$SIM_REVIEW" 'MAIN_RESTORE_BLOCKED=0'
has_literal "cleanup checkout 前掃 dirty" "$SIM_REVIEW" 'MAIN_DIRTY="$(/usr/bin/git -C "$MAIN_REPO" status --porcelain)"'
has_literal "dirty 留在 detached" "$SIM_REVIEW" 'main detached working tree is dirty; checkout main blocked; manual recovery required'
has_literal "dirty 標記人工恢復" "$SIM_REVIEW" 'MAIN_RESTORE_BLOCKED=1'
has_literal "cleanup checkout main" "$SIM_REVIEW" 'elif /usr/bin/git -C "$MAIN_REPO" checkout main; then'
has_adjacent_lines "正常還原釋放 detached 責任" "$SIM_REVIEW" \
  '      elif /usr/bin/git -C "$MAIN_REPO" checkout main; then' \
  '        MAIN_RESTORE_REQUIRED=0'
has_literal "正常還原清除 detached 狀態" "$SIM_REVIEW" '        MAIN_DETACHED=0'

RESTORE_OWNERSHIP_LINE="$(grep -nF 'MAIN_RESTORE_REQUIRED=1' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
DETACHED_CHECKOUT_LINE="$(grep -nF '/usr/bin/git -C "$MAIN_REPO" checkout --detach "$TARGET_COMMIT"' "$SIM_REVIEW" | head -n 1 | cut -d: -f1 || true)"
if [ -n "$RESTORE_OWNERSHIP_LINE" ] \
  && [ -n "$DETACHED_CHECKOUT_LINE" ] \
  && [ "$RESTORE_OWNERSHIP_LINE" -lt "$DETACHED_CHECKOUT_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL detached checkout 前必須預約 restore responsibility"
fi

CLEANUP_BLOCK="${QA_PLIST_REMOVE_BLOCK}
$(sed -n '/^cleanup_session_runtime_snapshots() {$/,/^}$/p' "$SIM_REVIEW")
$(sed -n '/^cleanup_sim_review() {$/,/^}$/p' "$SIM_REVIEW")"
CLEANUP_REMOVE_LINE="$(printf '%s\n' "$CLEANUP_BLOCK" | grep -nF 'rm -f "$MAIN_QA_FIREBASE_CONFIG"' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_DIRTY_LINE="$(printf '%s\n' "$CLEANUP_BLOCK" | grep -nF 'MAIN_DIRTY="$(/usr/bin/git -C "$MAIN_REPO" status --porcelain)"' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_CHECKOUT_LINE="$(printf '%s\n' "$CLEANUP_BLOCK" | grep -nF '/usr/bin/git -C "$MAIN_REPO" checkout main' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_DISPOSE_LINE="$(printf '%s\n' "$CLEANUP_BLOCK" | grep -nF 'if ! dispose_qa_identity_if_required; then' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_APP_STOP_LINE="$(printf '%s\n' "$CLEANUP_BLOCK" | grep -nF 'xcrun simctl terminate booted "$QA_BUNDLE_ID"' | head -n 1 | cut -d: -f1 || true)"
CLEANUP_METRO_STOP_LINE="$(printf '%s\n' "$CLEANUP_BLOCK" | grep -nF 'kill "$METRO_PID"' | head -n 1 | cut -d: -f1 || true)"
if [ -n "$CLEANUP_REMOVE_LINE" ] \
  && [ -n "$CLEANUP_DIRTY_LINE" ] \
  && [ -n "$CLEANUP_CHECKOUT_LINE" ] \
  && [ "$CLEANUP_REMOVE_LINE" -lt "$CLEANUP_DIRTY_LINE" ] \
  && [ "$CLEANUP_DIRTY_LINE" -lt "$CLEANUP_CHECKOUT_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL cleanup 必須先刪 QA 私密副本、掃 dirty、再 checkout main"
fi

if [ -n "$CLEANUP_DISPOSE_LINE" ] \
  && [ -n "$CLEANUP_APP_STOP_LINE" ] \
  && [ -n "$CLEANUP_METRO_STOP_LINE" ] \
  && [ -n "$CLEANUP_CHECKOUT_LINE" ] \
  && [ "$CLEANUP_DISPOSE_LINE" -lt "$CLEANUP_APP_STOP_LINE" ] \
  && [ "$CLEANUP_DISPOSE_LINE" -lt "$CLEANUP_METRO_STOP_LINE" ] \
  && [ "$CLEANUP_DISPOSE_LINE" -lt "$CLEANUP_CHECKOUT_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL cleanup 必須先 disposal、再停止 App Metro 與還原 git"
fi

DIRTY_GUARD_COUNT="$(grep -Fc 'MAIN_DIRTY="$(/usr/bin/git -C "$MAIN_REPO" status --porcelain)"' "$SIM_REVIEW" || true)"
if [ "$DIRTY_GUARD_COUNT" -ge 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL cleanup 與正常還原都必須掃 dirty"
fi

RESTORE_BLOCK="$(sed -n '/^## 還原$/,/^---$/p' "$SIM_REVIEW")"
RESTORE_DISPOSE_LINE="$(printf '%s\n' "$RESTORE_BLOCK" | grep -nF 'if ! dispose_qa_identity_if_required; then' | head -n 1 | cut -d: -f1 || true)"
RESTORE_APP_STOP_LINE="$(printf '%s\n' "$RESTORE_BLOCK" | grep -nF 'xcrun simctl terminate booted "$QA_BUNDLE_ID"' | head -n 1 | cut -d: -f1 || true)"
RESTORE_METRO_STOP_LINE="$(printf '%s\n' "$RESTORE_BLOCK" | grep -nF 'kill "$METRO_PID"' | head -n 1 | cut -d: -f1 || true)"
if [ -n "$RESTORE_DISPOSE_LINE" ] \
  && [ -n "$RESTORE_APP_STOP_LINE" ] \
  && [ -n "$RESTORE_METRO_STOP_LINE" ] \
  && [ "$RESTORE_DISPOSE_LINE" -lt "$RESTORE_APP_STOP_LINE" ] \
  && [ "$RESTORE_DISPOSE_LINE" -lt "$RESTORE_METRO_STOP_LINE" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL 正常還原必須先 disposal、再停止 App 與 Metro"
fi

echo "=== Synthetic commit contract ==="
has_literal "temporary directory" "$SIM_REVIEW" 'SYNTHETIC_TMP="$(/usr/bin/mktemp -d)"'
has_literal "尚不存在的 temporary index" "$SIM_REVIEW" 'SYNTHETIC_INDEX="$SYNTHETIC_TMP/index"'
has_literal "read-tree 不動 feat index" "$SIM_REVIEW" 'GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" read-tree "$ORIGINAL_HEAD"'
has_literal "temporary index 收入 working tree" "$SIM_REVIEW" 'GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" add -A -- .'
has_literal "write-tree" "$SIM_REVIEW" 'GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" write-tree'
has_literal "commit-tree" "$SIM_REVIEW" '/usr/bin/git -C "$IMPL_WORKTREE" commit-tree "$TARGET_TREE" -p "$ORIGINAL_HEAD"'
has_literal "feat HEAD 不移動" "$SIM_REVIEW" 'test "$(/usr/bin/git -C "$IMPL_WORKTREE" rev-parse HEAD)" = "$ORIGINAL_HEAD"'
lacks_pattern "sim-review 不得 Git 歷史改寫命令" "$SIM_REVIEW" '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(reset|stash|rebase)([[:space:]]|$)'
lacks_pattern "sim-review 不得 mixed reset 指示" "$SIM_REVIEW" 'mixed[[:space:]]+reset'
lacks_pattern "game-test 不得 Git 歷史改寫命令" "$GAME_TEST" '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(reset|stash|rebase)([[:space:]]|$)'
lacks_pattern "resolver 不得 Git 歷史改寫命令" "$RESOLVER" '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(reset|stash|rebase)([[:space:]]|$)'

if (
  set -e
  SYNTHETIC_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$SYNTHETIC_TEST_ROOT"' EXIT INT TERM
  SYNTHETIC_TEST_REPO="$SYNTHETIC_TEST_ROOT/repo"
  mkdir -p "$SYNTHETIC_TEST_REPO/ios"
  git -C "$SYNTHETIC_TEST_ROOT" init -q repo
  git -C "$SYNTHETIC_TEST_REPO" config user.name "Synthetic Test"
  git -C "$SYNTHETIC_TEST_REPO" config user.email "synthetic@example.invalid"
  printf '%s\n' 'ios/GoogleService-Info-QA.plist' > "$SYNTHETIC_TEST_REPO/.gitignore"
  printf '%s\n' 'base' > "$SYNTHETIC_TEST_REPO/tracked.txt"
  git -C "$SYNTHETIC_TEST_REPO" add .gitignore tracked.txt
  git -C "$SYNTHETIC_TEST_REPO" commit -qm base

  printf '%s\n' 'changed' > "$SYNTHETIC_TEST_REPO/tracked.txt"
  printf '%s\n' 'untracked' > "$SYNTHETIC_TEST_REPO/untracked.txt"
  printf '%s\n' 'private' > "$SYNTHETIC_TEST_REPO/ios/GoogleService-Info-QA.plist"

  BEFORE_HEAD="$(git -C "$SYNTHETIC_TEST_REPO" rev-parse HEAD)"
  BEFORE_INDEX_TREE="$(git -C "$SYNTHETIC_TEST_REPO" write-tree)"
  BEFORE_STATUS="$(git -C "$SYNTHETIC_TEST_REPO" status --porcelain=v1 --untracked-files=all)"

  SYNTHETIC_TMP="$(mktemp -d)"
  SYNTHETIC_INDEX="$SYNTHETIC_TMP/index"
  GIT_INDEX_FILE="$SYNTHETIC_INDEX" git -C "$SYNTHETIC_TEST_REPO" read-tree "$BEFORE_HEAD"
  GIT_INDEX_FILE="$SYNTHETIC_INDEX" git -C "$SYNTHETIC_TEST_REPO" add -A -- .
  if GIT_INDEX_FILE="$SYNTHETIC_INDEX" git -C "$SYNTHETIC_TEST_REPO" \
    ls-files --error-unmatch ios/GoogleService-Info-QA.plist >/dev/null 2>&1; then
    exit 1
  fi
  TARGET_TREE="$(GIT_INDEX_FILE="$SYNTHETIC_INDEX" git -C "$SYNTHETIC_TEST_REPO" write-tree)"
  TARGET_COMMIT="$(printf '%s\n' synthetic | git -C "$SYNTHETIC_TEST_REPO" commit-tree "$TARGET_TREE" -p "$BEFORE_HEAD")"

  test "$(git -C "$SYNTHETIC_TEST_REPO" show "$TARGET_COMMIT:tracked.txt")" = changed
  test "$(git -C "$SYNTHETIC_TEST_REPO" show "$TARGET_COMMIT:untracked.txt")" = untracked
  if git -C "$SYNTHETIC_TEST_REPO" show \
    "$TARGET_COMMIT:ios/GoogleService-Info-QA.plist" >/dev/null 2>&1; then
    exit 1
  fi
  test "$(git -C "$SYNTHETIC_TEST_REPO" rev-parse HEAD)" = "$BEFORE_HEAD"
  test "$(git -C "$SYNTHETIC_TEST_REPO" write-tree)" = "$BEFORE_INDEX_TREE"
  test "$(git -C "$SYNTHETIC_TEST_REPO" status --porcelain=v1 --untracked-files=all)" = "$BEFORE_STATUS"
  rm -f "$SYNTHETIC_INDEX"
  rmdir "$SYNTHETIC_TMP"
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL synthetic commit 動態契約"
fi

if (
  set -e
  PLIST_RACE_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$PLIST_RACE_TEST_ROOT"' EXIT INT TERM
  MAIN_QA_FIREBASE_CONFIG="$PLIST_RACE_TEST_ROOT/GoogleService-Info-QA.plist"
  MAIN_QA_FIREBASE_CONFIG_PATH="$MAIN_QA_FIREBASE_CONFIG"
  MAIN_QA_FIREBASE_CREATED=1
  MAIN_RESTORE_REQUIRED=0
  MAIN_DETACHED=0
  MAIN_REPO=""
  SYNTHETIC_INDEX=""
  SYNTHETIC_TMP=""
  METRO_PID=""
  READY_MARKER_LOG="$PLIST_RACE_TEST_ROOT/ready.log"
  READY_MARKER_LOG_PATH="$READY_MARKER_LOG"
  QA_BUNDLE_ID=""
  SIM_REVIEW_CLEANUP_RUNNING=0
  SESSION_FAILED=0
  RUNTIME_MARKER_SESSION_START_OFFSET=0
  RUNTIME_MARKER_SESSION_TAINTED=0
  dispose_qa_identity_if_required() { return 0; }
  cleanup_qa_fixtures_if_required() { return 0; }
  require_marker_filter_running() { return 0; }
  eval "$RUNTIME_SESSION_VALIDATE_BLOCK"
  eval "$CLEANUP_BLOCK"

  printf '%s\n' 'QA READY identityHash' > "$READY_MARKER_LOG"
  cleanup_sim_review
  test ! -e "$MAIN_QA_FIREBASE_CONFIG"
  test "$MAIN_QA_FIREBASE_CREATED" = 0
  test ! -e "$READY_MARKER_LOG_PATH"
  test -z "$READY_MARKER_LOG"

  MAIN_QA_FIREBASE_CONFIG="$MAIN_QA_FIREBASE_CONFIG_PATH"
  printf '%s\n' partial > "$MAIN_QA_FIREBASE_CONFIG"
  MAIN_QA_FIREBASE_CREATED=1
  cleanup_sim_review
  test ! -e "$MAIN_QA_FIREBASE_CONFIG"
  test "$MAIN_QA_FIREBASE_CREATED" = 0
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL QA plist 與 transient READY marker log cleanup 動態契約"
fi

if (
  set -e
  PLIST_DELETE_FAIL_ROOT="$(mktemp -d)"
  trap 'command rm -rf "$PLIST_DELETE_FAIL_ROOT"' EXIT INT TERM
  MAIN_REPO="$PLIST_DELETE_FAIL_ROOT/repo"
  git init -q -b main "$MAIN_REPO"
  git -C "$MAIN_REPO" config user.name "Plist Delete Failure Test"
  git -C "$MAIN_REPO" config user.email "plist-delete-failure@example.invalid"
  mkdir -p "$MAIN_REPO/ios"
  printf '%s\n' 'ios/GoogleService-Info-QA.plist' > "$MAIN_REPO/.gitignore"
  printf '%s\n' base > "$MAIN_REPO/tracked.txt"
  git -C "$MAIN_REPO" add .gitignore tracked.txt
  git -C "$MAIN_REPO" commit -qm base
  MAIN_START_HEAD="$(git -C "$MAIN_REPO" rev-parse HEAD)"
  BASE_TREE="$(git -C "$MAIN_REPO" rev-parse HEAD^{tree})"
  TARGET_COMMIT="$(printf '%s\n' detached | git -C "$MAIN_REPO" commit-tree "$BASE_TREE" -p "$MAIN_START_HEAD")"
  git -C "$MAIN_REPO" checkout -q --detach "$TARGET_COMMIT"

  MAIN_QA_FIREBASE_CONFIG="$MAIN_REPO/ios/GoogleService-Info-QA.plist"
  mkdir -p "$MAIN_QA_FIREBASE_CONFIG"
  MAIN_QA_FIREBASE_CREATED=1
  MAIN_RESTORE_REQUIRED=1
  MAIN_DETACHED=1
  MAIN_RESTORE_BLOCKED=0
  MAIN_ACTUAL_BRANCH=""
  MAIN_ACTUAL_HEAD=""
  MAIN_DIRTY=""
  SYNTHETIC_INDEX=""
  SYNTHETIC_TMP=""
  METRO_PID=""
  READY_MARKER_LOG=""
  QA_BUNDLE_ID=""
  SIM_REVIEW_CLEANUP_RUNNING=0
  SESSION_FAILED=0
  dispose_qa_identity_if_required() { return 0; }
  cleanup_qa_fixtures_if_required() { return 0; }
  eval "$CLEANUP_BLOCK"

  if cleanup_sim_review 2> "$PLIST_DELETE_FAIL_ROOT/stderr"; then
    exit 1
  fi

  test -e "$MAIN_QA_FIREBASE_CONFIG"
  test "$MAIN_QA_FIREBASE_CREATED" = 1
  test "$SESSION_FAILED" = 1
  test "$MAIN_RESTORE_BLOCKED" = 1
  test "$MAIN_RESTORE_REQUIRED" = 1
  test "$MAIN_DETACHED" = 1
  test -z "$(git -C "$MAIN_REPO" branch --show-current)"
  test "$(git -C "$MAIN_REPO" rev-parse HEAD)" = "$TARGET_COMMIT"
  grep -Fxq 'QA_FIREBASE_PRIVATE_COPY_CLEANUP_FAILED' "$PLIST_DELETE_FAIL_ROOT/stderr"
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL QA plist deletion failure 必須保留 ownership 並阻止 restore"
fi

if (
  set -e
  RESTORE_RACE_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$RESTORE_RACE_TEST_ROOT"' EXIT INT TERM
  MAIN_REPO="$RESTORE_RACE_TEST_ROOT/repo"
  git init -q -b main "$MAIN_REPO"
  git -C "$MAIN_REPO" config user.name "Restore Race Test"
  git -C "$MAIN_REPO" config user.email "restore-race@example.invalid"
  printf '%s\n' base > "$MAIN_REPO/tracked.txt"
  git -C "$MAIN_REPO" add tracked.txt
  git -C "$MAIN_REPO" commit -qm base
  MAIN_START_HEAD="$(git -C "$MAIN_REPO" rev-parse HEAD)"
  BASE_TREE="$(git -C "$MAIN_REPO" rev-parse HEAD^{tree})"
  TARGET_COMMIT="$(printf '%s\n' detached | git -C "$MAIN_REPO" commit-tree "$BASE_TREE" -p "$MAIN_START_HEAD")"
  MAIN_RESTORE_REQUIRED=1
  MAIN_DETACHED=0
  MAIN_RESTORE_BLOCKED=0
  MAIN_QA_FIREBASE_CONFIG=""
  MAIN_QA_FIREBASE_CREATED=0
  SYNTHETIC_INDEX=""
  SYNTHETIC_TMP=""
  METRO_PID=""
  QA_BUNDLE_ID=""
  SIM_REVIEW_CLEANUP_RUNNING=0
  SESSION_FAILED=0
  dispose_qa_identity_if_required() { return 0; }
  cleanup_qa_fixtures_if_required() { return 0; }
  eval "$CLEANUP_BLOCK"

  cleanup_sim_review
  test "$MAIN_RESTORE_REQUIRED" = 0
  test "$MAIN_DETACHED" = 0
  test "$(git -C "$MAIN_REPO" branch --show-current)" = main

  MAIN_RESTORE_REQUIRED=1
  git -C "$MAIN_REPO" checkout -q --detach "$TARGET_COMMIT"
  MAIN_DETACHED=0
  cleanup_sim_review
  test "$MAIN_RESTORE_REQUIRED" = 0
  test "$MAIN_DETACHED" = 0
  test "$(git -C "$MAIN_REPO" branch --show-current)" = main
  test "$(git -C "$MAIN_REPO" rev-parse HEAD)" = "$MAIN_START_HEAD"
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL main pre-checkout 與 post-checkout interruption cleanup 動態契約"
fi

if (
  set -e
  CLEANUP_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$CLEANUP_TEST_ROOT"' EXIT INT TERM
  MAIN_REPO="$CLEANUP_TEST_ROOT/repo"
  git init -q -b main "$MAIN_REPO"
  git -C "$MAIN_REPO" config user.name "Cleanup Test"
  git -C "$MAIN_REPO" config user.email "cleanup@example.invalid"
  mkdir -p "$MAIN_REPO/ios"
  printf '%s\n' 'base' > "$MAIN_REPO/tracked.txt"
  git -C "$MAIN_REPO" add tracked.txt
  git -C "$MAIN_REPO" commit -qm base
  BASE_HEAD="$(git -C "$MAIN_REPO" rev-parse HEAD)"
  BASE_TREE="$(git -C "$MAIN_REPO" rev-parse HEAD^{tree})"
  TARGET_COMMIT="$(printf '%s\n' detached | git -C "$MAIN_REPO" commit-tree "$BASE_TREE" -p "$BASE_HEAD")"
  git -C "$MAIN_REPO" checkout -q --detach "$TARGET_COMMIT"
  MAIN_DETACHED=1

  MAIN_QA_FIREBASE_CONFIG="$MAIN_REPO/ios/GoogleService-Info-QA.plist"
  printf '%s\n' private > "$MAIN_QA_FIREBASE_CONFIG"
  MAIN_QA_FIREBASE_CREATED=1
  MAIN_RESTORE_BLOCKED=0

  cleanup_sim_review() {
    if [ "$MAIN_QA_FIREBASE_CREATED" = 1 ] && [ -n "$MAIN_QA_FIREBASE_CONFIG" ]; then
      rm -f "$MAIN_QA_FIREBASE_CONFIG"
      MAIN_QA_FIREBASE_CREATED=0
    fi
    if [ "$MAIN_DETACHED" = 1 ] && [ -n "$MAIN_REPO" ]; then
      MAIN_DIRTY="$(git -C "$MAIN_REPO" status --porcelain)"
      if [ -n "$MAIN_DIRTY" ]; then
        MAIN_RESTORE_BLOCKED=1
      elif git -C "$MAIN_REPO" checkout -q main; then
        MAIN_DETACHED=0
      fi
    fi
  }

  cleanup_sim_review
  test ! -e "$MAIN_QA_FIREBASE_CONFIG"
  test "$MAIN_QA_FIREBASE_CREATED" = 0
  test "$MAIN_DETACHED" = 0
  test "$MAIN_RESTORE_BLOCKED" = 0
  test "$(git -C "$MAIN_REPO" branch --show-current)" = main
  test -z "$(git -C "$MAIN_REPO" status --porcelain)"
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL detached main cleanup 動態契約"
fi

if (
  set -e
  DIRTY_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$DIRTY_TEST_ROOT"' EXIT INT TERM
  MAIN_REPO="$DIRTY_TEST_ROOT/repo"
  git init -q -b main "$MAIN_REPO"
  git -C "$MAIN_REPO" config user.name "Dirty Cleanup Test"
  git -C "$MAIN_REPO" config user.email "dirty-cleanup@example.invalid"
  mkdir -p "$MAIN_REPO/ios"
  printf '%s\n' base > "$MAIN_REPO/tracked.txt"
  git -C "$MAIN_REPO" add tracked.txt
  git -C "$MAIN_REPO" commit -qm base
  BASE_HEAD="$(git -C "$MAIN_REPO" rev-parse HEAD)"
  BASE_TREE="$(git -C "$MAIN_REPO" rev-parse HEAD^{tree})"
  TARGET_COMMIT="$(printf '%s\n' detached | git -C "$MAIN_REPO" commit-tree "$BASE_TREE" -p "$BASE_HEAD")"
  git -C "$MAIN_REPO" checkout -q --detach "$TARGET_COMMIT"
  MAIN_DETACHED=1
  MAIN_RESTORE_BLOCKED=0

  MAIN_QA_FIREBASE_CONFIG="$MAIN_REPO/ios/GoogleService-Info-QA.plist"
  printf '%s\n' private > "$MAIN_QA_FIREBASE_CONFIG"
  MAIN_QA_FIREBASE_CREATED=1
  printf '%s\n' preserve > "$MAIN_REPO/preserve-user-change.txt"

  cleanup_sim_review() {
    if [ "$MAIN_QA_FIREBASE_CREATED" = 1 ] && [ -n "$MAIN_QA_FIREBASE_CONFIG" ]; then
      rm -f "$MAIN_QA_FIREBASE_CONFIG"
      MAIN_QA_FIREBASE_CREATED=0
    fi
    if [ "$MAIN_DETACHED" = 1 ] && [ -n "$MAIN_REPO" ]; then
      MAIN_DIRTY="$(git -C "$MAIN_REPO" status --porcelain)"
      if [ -n "$MAIN_DIRTY" ]; then
        MAIN_RESTORE_BLOCKED=1
        echo 'main detached working tree is dirty; checkout main blocked; manual recovery required' >&2
      elif git -C "$MAIN_REPO" checkout -q main; then
        MAIN_DETACHED=0
      fi
    fi
  }

  cleanup_sim_review 2> "$DIRTY_TEST_ROOT/stderr"
  test ! -e "$MAIN_QA_FIREBASE_CONFIG"
  test -e "$MAIN_REPO/preserve-user-change.txt"
  test "$MAIN_QA_FIREBASE_CREATED" = 0
  test "$MAIN_DETACHED" = 1
  test "$MAIN_RESTORE_BLOCKED" = 1
  test -z "$(git -C "$MAIN_REPO" branch --show-current)"
  grep -Fq 'manual recovery required' "$DIRTY_TEST_ROOT/stderr"
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL dirty detached cleanup 動態契約"
fi

if (
  set -e
  LIFECYCLE_TEST_ROOT="$(mktemp -d)"
  trap 'rm -rf "$LIFECYCLE_TEST_ROOT"' EXIT INT TERM
  LIFECYCLE_TRACE="$LIFECYCLE_TEST_ROOT/trace"
  LIFECYCLE_STDERR="$LIFECYCLE_TEST_ROOT/stderr"
  : > "$LIFECYCLE_TRACE"
  : > "$LIFECYCLE_STDERR"

  IDENTITY_TEARDOWN_POSSIBLE=0
  IDENTITY_TEARDOWN_RUNNING=0
  IDENTITY_TEARDOWN_ATTEMPTED=0
  IDENTITY_TEARDOWN_FAILED=0
  IDENTITY_TEARDOWN_FAILURE_REPORTED=0
  SIM_REVIEW_CLEANUP_RUNNING=0
  SESSION_FAILED=0
  DISPOSAL_RESULT=0

  run_and_validate_qa_identity_disposal() {
    printf '%s\n' dispose >> "$LIFECYCLE_TRACE"
    [ "$DISPOSAL_RESULT" = 0 ]
  }

  report_identity_teardown_failure() {
    SESSION_FAILED=1
    if [ "$IDENTITY_TEARDOWN_FAILURE_REPORTED" = 0 ]; then
      echo 'QA anonymous account cleanup failed; account not cleaned or proven absent' >&2
      IDENTITY_TEARDOWN_FAILURE_REPORTED=1
    fi
  }

  dispose_qa_identity_if_required() {
    local disposal_status=0
    [ "$IDENTITY_TEARDOWN_POSSIBLE" = 1 ] || return 0
    if [ "$IDENTITY_TEARDOWN_RUNNING" = 1 ] || [ "$IDENTITY_TEARDOWN_ATTEMPTED" = 1 ]; then
      if [ "$IDENTITY_TEARDOWN_FAILED" = 1 ]; then
        report_identity_teardown_failure
        return 1
      fi
      return 0
    fi
    IDENTITY_TEARDOWN_RUNNING=1
    IDENTITY_TEARDOWN_ATTEMPTED=1
    IDENTITY_TEARDOWN_FAILED=1
    if run_and_validate_qa_identity_disposal; then
      IDENTITY_TEARDOWN_POSSIBLE=0
      IDENTITY_TEARDOWN_FAILED=0
    else
      report_identity_teardown_failure
      disposal_status=1
    fi
    IDENTITY_TEARDOWN_RUNNING=0
    return "$disposal_status"
  }

  cleanup_sim_review() {
    local cleanup_status=0
    if [ "$SIM_REVIEW_CLEANUP_RUNNING" = 1 ]; then
      return 0
    fi
    SIM_REVIEW_CLEANUP_RUNNING=1
    if ! dispose_qa_identity_if_required; then
      cleanup_status=1
    fi
    printf '%s\n' stop-app >> "$LIFECYCLE_TRACE"
    printf '%s\n' stop-metro >> "$LIFECYCLE_TRACE"
    printf '%s\n' restore-git >> "$LIFECYCLE_TRACE"
    SIM_REVIEW_CLEANUP_RUNNING=0
    if [ "$SESSION_FAILED" = 1 ]; then
      cleanup_status=1
    fi
    [ "$cleanup_status" = 0 ]
  }

  cleanup_sim_review
  if grep -Fq dispose "$LIFECYCLE_TRACE"; then
    exit 1
  fi

  : > "$LIFECYCLE_TRACE"
  IDENTITY_TEARDOWN_POSSIBLE=1
  cleanup_sim_review
  test "$(sed -n '1,4p' "$LIFECYCLE_TRACE")" = "$(printf '%s\n' dispose stop-app stop-metro restore-git)"
  cleanup_sim_review
  test "$(grep -Fc dispose "$LIFECYCLE_TRACE")" = 1
  test "$IDENTITY_TEARDOWN_POSSIBLE" = 0

  : > "$LIFECYCLE_TRACE"
  IDENTITY_TEARDOWN_POSSIBLE=1
  IDENTITY_TEARDOWN_RUNNING=0
  IDENTITY_TEARDOWN_ATTEMPTED=0
  IDENTITY_TEARDOWN_FAILED=0
  IDENTITY_TEARDOWN_FAILURE_REPORTED=0
  SESSION_FAILED=0
  DISPOSAL_RESULT=1
  if cleanup_sim_review 2> "$LIFECYCLE_STDERR"; then
    exit 1
  fi
  if cleanup_sim_review 2>> "$LIFECYCLE_STDERR"; then
    exit 1
  fi
  test "$(sed -n '1,4p' "$LIFECYCLE_TRACE")" = "$(printf '%s\n' dispose stop-app stop-metro restore-git)"
  test "$(grep -Fc dispose "$LIFECYCLE_TRACE")" = 1
  test "$IDENTITY_TEARDOWN_POSSIBLE" = 1
  test "$IDENTITY_TEARDOWN_FAILED" = 1
  test "$SESSION_FAILED" = 1
  test "$(grep -Fc 'account not cleaned or proven absent' "$LIFECYCLE_STDERR")" = 1
); then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL identity teardown lifecycle 動態契約"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
