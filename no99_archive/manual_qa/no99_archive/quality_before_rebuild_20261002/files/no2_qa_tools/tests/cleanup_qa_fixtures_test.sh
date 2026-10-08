#!/usr/bin/env bash

set -u

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
SOURCE_HELPER="$TEST_DIR/../cleanup_qa_fixtures.sh"

if [ ! -f "$SOURCE_HELPER" ]; then
    printf '%s\n' 'FAIL cleanup helper 不存在'
    exit 1
fi

TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-qa-fixtures-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

RUNTIME_DIR="$TEST_TMP/runtime"
STUB_BIN="$TEST_TMP/bin"
HOSTILE_BIN="$TEST_TMP/hostile-bin"
STUB_LOG="$TEST_TMP/firebase-args.log"
STUB_ENV_LOG="$TEST_TMP/firebase-env.log"
STUB_STDIN_LOG="$TEST_TMP/transport-stdin.log"
HOSTILE_SENTINEL="$TEST_TMP/hostile-sentinel.log"
STDOUT_FILE="$TEST_TMP/stdout.log"
STDERR_FILE="$TEST_TMP/stderr.log"
mkdir -p "$RUNTIME_DIR" "$STUB_BIN" "$HOSTILE_BIN"
HELPER="$RUNTIME_DIR/cleanup_qa_fixtures.sh"
DELETE_HELPER="$RUNTIME_DIR/delete_qa_fixture_subtree.py"
cp -P "$SOURCE_HELPER" "$HELPER"

cat > "$DELETE_HELPER" <<'STUB'
#!/usr/bin/env python3
import os
import pathlib
import sys

arguments = ["-I", sys.argv[0], *sys.argv[1:]]
pathlib.Path(os.environ["QA_FIREBASE_STUB_LOG"]).write_text(
    "".join(f"{argument}\n" for argument in arguments),
    encoding="utf-8",
)
pathlib.Path(os.environ["QA_DELETE_STUB_STDIN_LOG"]).write_text(
    sys.stdin.read(),
    encoding="utf-8",
)
environment_names = (
    "FIRESTORE_EMULATOR_HOST",
    "FIRESTORE_URL",
    "FIREBASE_EMULATOR_HUB",
    "FIREBASE_AUTH_EMULATOR_HOST",
    "FIREBASE_GOOGLE_URL",
    "FIREBASE_TOKEN_URL",
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH",
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE",
    "CLOUDSDK_PROXY_ADDRESS",
    "SSL_CERT_FILE",
    "SSLKEYLOGFILE",
    "PYTHONPATH",
    "BASH_ENV",
    "HTTPS_PROXY",
    "NO_PROXY",
)
pathlib.Path(os.environ["QA_FIREBASE_STUB_ENV_LOG"]).write_text(
    "".join(f"{name}={os.environ.get(name, 'unset')}\n" for name in environment_names),
    encoding="utf-8",
)
secret = os.environ["QA_FIREBASE_STUB_SECRET"]
print(f"raw transport stdout {secret}")
print(f"raw transport stderr {secret}", file=sys.stderr)
raise SystemExit(int(os.environ.get("QA_DELETE_STUB_EXIT", "0")))
STUB
DELETE_HELPER_REAL=$(cd -P "$(dirname "$DELETE_HELPER")" && pwd -P)/$(basename "$DELETE_HELPER")

cat > "$STUB_BIN/firebase" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$@" > "$QA_FIREBASE_STUB_LOG"
printf '%s\n' \
    "FIRESTORE_EMULATOR_HOST=${FIRESTORE_EMULATOR_HOST-unset}" \
    "FIRESTORE_URL=${FIRESTORE_URL-unset}" \
    "FIREBASE_EMULATOR_HUB=${FIREBASE_EMULATOR_HUB-unset}" \
    "FIREBASE_AUTH_EMULATOR_HOST=${FIREBASE_AUTH_EMULATOR_HOST-unset}" \
    "FIREBASE_GOOGLE_URL=${FIREBASE_GOOGLE_URL-unset}" \
    "FIREBASE_TOKEN_URL=${FIREBASE_TOKEN_URL-unset}" \
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH=${CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH-unset}" \
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE=${CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE-unset}" \
    "CLOUDSDK_PROXY_ADDRESS=${CLOUDSDK_PROXY_ADDRESS-unset}" \
    "SSL_CERT_FILE=${SSL_CERT_FILE-unset}" \
    "SSLKEYLOGFILE=${SSLKEYLOGFILE-unset}" \
    "PYTHONPATH=${PYTHONPATH-unset}" \
    "BASH_ENV=${BASH_ENV-unset}" \
    "HTTPS_PROXY=${HTTPS_PROXY-unset}" \
    "NO_PROXY=${NO_PROXY-unset}" \
    > "$QA_FIREBASE_STUB_ENV_LOG"
printf '%s\n' "raw firebase stdout $QA_FIREBASE_STUB_SECRET"
printf '%s\n' "raw firebase stderr $QA_FIREBASE_STUB_SECRET" >&2
exit "${QA_FIREBASE_STUB_EXIT:-0}"
STUB
chmod +x "$STUB_BIN/firebase"

cat > "$STUB_BIN/python3" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$@" > "$QA_FIREBASE_STUB_LOG"
cat > "$QA_DELETE_STUB_STDIN_LOG"
printf '%s\n' \
    "FIRESTORE_EMULATOR_HOST=${FIRESTORE_EMULATOR_HOST-unset}" \
    "FIRESTORE_URL=${FIRESTORE_URL-unset}" \
    "FIREBASE_EMULATOR_HUB=${FIREBASE_EMULATOR_HUB-unset}" \
    "FIREBASE_AUTH_EMULATOR_HOST=${FIREBASE_AUTH_EMULATOR_HOST-unset}" \
    "FIREBASE_GOOGLE_URL=${FIREBASE_GOOGLE_URL-unset}" \
    "FIREBASE_TOKEN_URL=${FIREBASE_TOKEN_URL-unset}" \
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH=${CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH-unset}" \
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE=${CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE-unset}" \
    "CLOUDSDK_PROXY_ADDRESS=${CLOUDSDK_PROXY_ADDRESS-unset}" \
    "SSL_CERT_FILE=${SSL_CERT_FILE-unset}" \
    "SSLKEYLOGFILE=${SSLKEYLOGFILE-unset}" \
    "PYTHONPATH=${PYTHONPATH-unset}" \
    "BASH_ENV=${BASH_ENV-unset}" \
    "HTTPS_PROXY=${HTTPS_PROXY-unset}" \
    "NO_PROXY=${NO_PROXY-unset}" \
    > "$QA_FIREBASE_STUB_ENV_LOG"
printf '%s\n' "raw transport stdout $QA_FIREBASE_STUB_SECRET"
printf '%s\n' "raw transport stderr $QA_FIREBASE_STUB_SECRET" >&2
exit "${QA_DELETE_STUB_EXIT:-0}"
STUB
chmod +x "$STUB_BIN/python3"

cat > "$HOSTILE_BIN/python3" <<'STUB'
#!/usr/bin/env bash
set -u
cat >/dev/null
printf '%s\n' "$QA_FIREBASE_STUB_SECRET" > "$QA_HOSTILE_SENTINEL"
exit 0
STUB
chmod +x "$HOSTILE_BIN/python3"

cat > "$HOSTILE_BIN/env" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$QA_FIREBASE_STUB_SECRET" > "$QA_HOSTILE_SENTINEL"
exit 0
STUB
chmod +x "$HOSTILE_BIN/env"

PASS=0
FAIL=0
SESSION_UID='qaFixtureUid0123456789'

pass() {
    PASS=$((PASS + 1))
}

fail() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
}

run_helper() {
    local input="$1"
    local stub_exit="$2"
    shift 2
    : > "$STUB_LOG"
    : > "$STUB_ENV_LOG"
    : > "$STUB_STDIN_LOG"
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    printf '%b' "$input" | \
        env -u FIRESTORE_EMULATOR_HOST \
            -u FIRESTORE_URL \
            -u FIREBASE_EMULATOR_HUB \
            -u FIREBASE_AUTH_EMULATOR_HOST \
            -u FIREBASE_GOOGLE_URL \
            -u FIREBASE_TOKEN_URL \
            -u CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH \
            -u CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
            -u CLOUDSDK_PROXY_TYPE \
            -u CLOUDSDK_PROXY_ADDRESS \
            -u CLOUDSDK_PROXY_PORT \
            -u CLOUDSDK_PROXY_USERNAME \
            -u CLOUDSDK_PROXY_PASSWORD \
            -u CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
            -u CLOUDSDK_AUTH_TOKEN_HOST \
            -u CLOUDSDK_CONFIG \
            -u CLOUDSDK_ACTIVE_CONFIG_NAME \
            -u GCE_METADATA_HOST \
            -u GCE_METADATA_ROOT \
            -u GOOGLE_API_USE_MTLS_ENDPOINT \
            -u SSL_CERT_FILE \
            -u SSL_CERT_DIR \
            -u SSLKEYLOGFILE \
            -u REQUESTS_CA_BUNDLE \
            -u CURL_CA_BUNDLE \
            -u NODE_EXTRA_CA_CERTS \
            -u GRPC_DEFAULT_SSL_ROOTS_FILE_PATH \
            -u PYTHONPATH \
            -u PYTHONHOME \
            -u PYTHONSTARTUP \
            -u PYTHONINSPECT \
            -u PYTHONBREAKPOINT \
            -u BASH_ENV \
            -u ENV \
            -u SHELLOPTS \
            -u BASHOPTS \
            -u BASH_XTRACEFD \
            -u PS4 \
            -u DYLD_INSERT_LIBRARIES \
            -u DYLD_LIBRARY_PATH \
            -u LD_PRELOAD \
            -u LD_LIBRARY_PATH \
            -u HTTP_PROXY \
            -u HTTPS_PROXY \
            -u ALL_PROXY \
            -u http_proxy \
            -u https_proxy \
            -u all_proxy \
            -u NO_PROXY \
            -u no_proxy \
        PATH="$STUB_BIN:$PATH" \
        QA_FIREBASE_STUB_LOG="$STUB_LOG" \
        QA_FIREBASE_STUB_ENV_LOG="$STUB_ENV_LOG" \
        QA_DELETE_STUB_STDIN_LOG="$STUB_STDIN_LOG" \
        QA_FIREBASE_STUB_SECRET="$SESSION_UID" \
        QA_FIREBASE_STUB_EXIT="$stub_exit" \
        QA_DELETE_STUB_EXIT="$stub_exit" \
        bash "$HELPER" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
}

run_helper_with_override() {
    local override_name="$1"
    local input="$2"
    shift 2
    : > "$STUB_LOG"
    : > "$STUB_ENV_LOG"
    : > "$STUB_STDIN_LOG"
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    printf '%b' "$input" | \
        env "$override_name=127.0.0.1:8080" \
            PATH="$STUB_BIN:$PATH" \
            QA_FIREBASE_STUB_LOG="$STUB_LOG" \
            QA_FIREBASE_STUB_ENV_LOG="$STUB_ENV_LOG" \
            QA_DELETE_STUB_STDIN_LOG="$STUB_STDIN_LOG" \
            QA_FIREBASE_STUB_SECRET="$SESSION_UID" \
            QA_FIREBASE_STUB_EXIT=0 \
            QA_DELETE_STUB_EXIT=0 \
            bash "$HELPER" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
}

run_helper_with_hostile_path() {
    : > "$STUB_LOG"
    : > "$STUB_ENV_LOG"
    : > "$STUB_STDIN_LOG"
    : > "$HOSTILE_SENTINEL"
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    printf '%s\n' "$SESSION_UID" | \
        /usr/bin/env \
            PATH="$HOSTILE_BIN:/usr/bin:/bin" \
            QA_FIREBASE_STUB_LOG="$STUB_LOG" \
            QA_FIREBASE_STUB_ENV_LOG="$STUB_ENV_LOG" \
            QA_DELETE_STUB_STDIN_LOG="$STUB_STDIN_LOG" \
            QA_FIREBASE_STUB_SECRET="$SESSION_UID" \
            QA_DELETE_STUB_EXIT=0 \
            QA_HOSTILE_SENTINEL="$HOSTILE_SENTINEL" \
            /bin/bash "$HELPER" \
                --project susugigi-qa \
                --session-uid-stdin \
                > "$STDOUT_FILE" 2> "$STDERR_FILE"
}

run_helper_with_imported_function() {
    local function_name="$1"
    local function_definition
    function_definition='() { /usr/bin/printf "%s\n" "$QA_FIREBASE_STUB_SECRET" > "$QA_HOSTILE_SENTINEL"; return 23; }'
    : > "$STUB_LOG"
    : > "$STUB_ENV_LOG"
    : > "$STUB_STDIN_LOG"
    : > "$HOSTILE_SENTINEL"
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    printf '%s\n' "$SESSION_UID" | \
        /usr/bin/env \
            "BASH_FUNC_${function_name}%%=$function_definition" \
            PATH="$STUB_BIN:/usr/bin:/bin" \
            QA_FIREBASE_STUB_LOG="$STUB_LOG" \
            QA_FIREBASE_STUB_ENV_LOG="$STUB_ENV_LOG" \
            QA_DELETE_STUB_STDIN_LOG="$STUB_STDIN_LOG" \
            QA_FIREBASE_STUB_SECRET="$SESSION_UID" \
            QA_DELETE_STUB_EXIT=0 \
            QA_HOSTILE_SENTINEL="$HOSTILE_SENTINEL" \
            /bin/bash "$HELPER" \
                --project susugigi-qa \
                --session-uid-stdin \
                > "$STDOUT_FILE" 2> "$STDERR_FILE"
}

assert_no_uid_or_raw_response() {
    local name="$1"
    if grep -Fq "$SESSION_UID" "$STDOUT_FILE" "$STDERR_FILE" || \
       grep -Fq 'raw firebase' "$STDOUT_FILE" "$STDERR_FILE" || \
       grep -Fq 'raw transport' "$STDOUT_FILE" "$STDERR_FILE"; then
        fail "$name 洩漏 uid 或 raw response"
    else
        pass
    fi
}

run_helper "$SESSION_UID\n" 0 \
    --project susugigi-qa \
    --session-uid-stdin
status=$?
if [ "$status" -eq 0 ]; then
    pass
else
    fail 'QA project cleanup 應成功'
fi
if diff -u <(printf '%s\n' \
    -I \
    "$DELETE_HELPER_REAL" \
    --project \
    susugigi-qa \
    --session-uid-stdin) "$STUB_LOG" >/dev/null && \
   [ "$(cat "$STUB_STDIN_LOG")" = "$SESSION_UID" ] && \
   ! grep -Fq "$SESSION_UID" "$STUB_LOG"; then
    pass
else
    fail 'delete transport 必須只由 stdin 接收 UID'
fi
if [ "$(cat "$STDOUT_FILE")" = 'QA fixture cleanup completed' ] && \
   [ ! -s "$STDERR_FILE" ]; then
    pass
else
    fail '成功輸出不是固定安全訊息'
fi
assert_no_uid_or_raw_response '成功路徑'
for helper_status in 20 21 22 24 25 26 27 75 76 99; do
    run_helper "$SESSION_UID\n" "$helper_status" \
        --project susugigi-qa --session-uid-stdin
    status=$?
    expected_status="$helper_status"
    [ "$helper_status" != 99 ] || expected_status=1
    if [ "$status" = "$expected_status" ] && [ ! -s "$STDOUT_FILE" ] \
        && [ "$(cat "$STDERR_FILE")" = 'QA fixture cleanup failed' ]; then
        pass
    else
        fail 'typed failure status 必須使用封閉對照'
    fi
    assert_no_uid_or_raw_response 'typed failure'
done
if diff -u <(printf '%s\n' \
    'FIRESTORE_EMULATOR_HOST=unset' \
    'FIRESTORE_URL=unset' \
    'FIREBASE_EMULATOR_HUB=unset' \
    'FIREBASE_AUTH_EMULATOR_HOST=unset' \
    'FIREBASE_GOOGLE_URL=unset' \
    'FIREBASE_TOKEN_URL=unset' \
    'CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH=unset' \
    'CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE=unset' \
    'CLOUDSDK_PROXY_ADDRESS=unset' \
    'SSL_CERT_FILE=unset' \
    'SSLKEYLOGFILE=unset' \
    'PYTHONPATH=unset' \
    'BASH_ENV=unset' \
    'HTTPS_PROXY=unset' \
    'NO_PROXY=unset') "$STUB_ENV_LOG" >/dev/null; then
    pass
else
    fail 'delete transport child environment 必須移除 endpoint overrides'
fi

for override_name in \
    FIRESTORE_EMULATOR_HOST \
    FIRESTORE_URL \
    FIREBASE_EMULATOR_HUB \
    FIREBASE_AUTH_EMULATOR_HOST \
    FIREBASE_AUTH_URL \
    FIREBASE_AUTHPROXY_URL \
    FIREBASE_AUTH_MANAGEMENT_URL \
    FIREBASE_IDENTITY_URL \
    FIREBASE_API_URL \
    FIREBASE_GOOGLE_URL \
    FIREBASE_TOKEN_URL \
    CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH \
    CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
    CLOUDSDK_PROXY_TYPE \
    CLOUDSDK_PROXY_ADDRESS \
    CLOUDSDK_PROXY_PORT \
    CLOUDSDK_PROXY_USERNAME \
    CLOUDSDK_PROXY_PASSWORD \
    CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
    CLOUDSDK_AUTH_TOKEN_HOST \
    CLOUDSDK_CONFIG \
    CLOUDSDK_ACTIVE_CONFIG_NAME \
    GCE_METADATA_HOST \
    GCE_METADATA_ROOT \
    GOOGLE_API_USE_MTLS_ENDPOINT \
    SSL_CERT_FILE \
    SSL_CERT_DIR \
    SSLKEYLOGFILE \
    REQUESTS_CA_BUNDLE \
    CURL_CA_BUNDLE \
    NODE_EXTRA_CA_CERTS \
    GRPC_DEFAULT_SSL_ROOTS_FILE_PATH \
    PYTHONPATH \
    PYTHONHOME \
    PYTHONSTARTUP \
    PYTHONINSPECT \
    PYTHONBREAKPOINT \
    BASH_ENV \
    ENV \
    LD_PRELOAD \
    LD_LIBRARY_PATH \
    HTTP_PROXY \
    HTTPS_PROXY \
    ALL_PROXY \
    http_proxy \
    https_proxy \
    all_proxy \
    NO_PROXY \
    no_proxy; do
    run_helper_with_override "$override_name" "$SESSION_UID\n" \
        --project susugigi-qa \
        --session-uid-stdin
    status=$?
    if [ "$status" -eq 2 ] && \
       [ ! -s "$STUB_LOG" ] && \
       [ ! -s "$STUB_ENV_LOG" ] && \
       [ ! -s "$STDOUT_FILE" ] && \
       [ "$(cat "$STDERR_FILE")" = 'QA fixture cleanup rejected' ]; then
        pass
    else
        fail "$override_name 必須在 delete transport 前固定拒絕"
    fi
    assert_no_uid_or_raw_response "$override_name 拒絕"
done

# macOS 的 dynamic loader 會在 bash 啟動前清掉 DYLD_*，無法用 child runtime
# 注入重現。用 source contract 鎖住 wrapper 的 preflight 拒絕與 child 清除兩處。
for loader_override in DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH; do
    if [ "$(grep -Fc "$loader_override" "$SOURCE_HELPER")" -ge 2 ]; then
        pass
    else
        fail "$loader_override 必須同時出現在 preflight denylist 與 child env 清除"
    fi
done

# SHELLOPTS、BASHOPTS 與 PS4 是 Bash 內建非空變數，helper 內不能把非空當成
# 注入判準；它只負責不把這些值傳進 child，真正 startup 邊界由 trusted launcher 驗。
for shell_startup_override in SHELLOPTS BASHOPTS BASH_XTRACEFD PS4; do
    if grep -Fq -- "-u $shell_startup_override" "$SOURCE_HELPER"; then
        pass
    else
        fail "$shell_startup_override 必須從 child environment 清除"
    fi
done

run_helper "$SESSION_UID\n" 0 \
    --project susugigi-c4fb1 \
    --session-uid-stdin
status=$?
if [ "$status" -ne 0 ] && [ ! -s "$STUB_LOG" ]; then
    pass
else
    fail 'Production project 必須在 transport 前拒絕'
fi
assert_no_uid_or_raw_response 'Production 拒絕'

run_helper "$SESSION_UID\n" 0 \
    --project another-project \
    --session-uid-stdin
status=$?
if [ "$status" -ne 0 ] && [ ! -s "$STUB_LOG" ]; then
    pass
else
    fail '非 canonical QA project 必須拒絕'
fi

run_helper '' 0 \
    --project susugigi-qa \
    --session-uid "$SESSION_UID"
status=$?
if [ "$status" -ne 0 ] && [ ! -s "$STUB_LOG" ]; then
    pass
else
    fail 'UID argv 必須拒絕'
fi
assert_no_uid_or_raw_response 'UID argv 拒絕'

run_helper '../escape\n' 0 \
    --project susugigi-qa \
    --session-uid-stdin
status=$?
if [ "$status" -ne 0 ] && [ ! -s "$STUB_LOG" ]; then
    pass
else
    fail 'path escape UID 必須拒絕'
fi

run_helper "$SESSION_UID\nsecond-line\n" 0 \
    --project susugigi-qa \
    --session-uid-stdin
status=$?
if [ "$status" -ne 0 ] && [ ! -s "$STUB_LOG" ]; then
    pass
else
    fail '多行 stdin 必須拒絕'
fi

run_helper "$SESSION_UID\ntrailing-bytes" 0 \
    --project susugigi-qa \
    --session-uid-stdin
status=$?
if [ "$status" -eq 2 ] && \
   [ ! -s "$STUB_LOG" ] && \
   [ ! -s "$STUB_STDIN_LOG" ]; then
    pass
else
    fail '無結尾換行的 trailing stdin bytes 必須拒絕'
fi
assert_no_uid_or_raw_response 'trailing stdin bytes 拒絕'

run_helper_with_hostile_path
status=$?
if [ "$status" -eq 0 ] && \
   [ ! -s "$HOSTILE_SENTINEL" ] && \
   [ -s "$STUB_LOG" ] && \
   [ "$(cat "$STUB_STDIN_LOG")" = "$SESSION_UID" ]; then
    pass
else
    fail 'cleanup helper 必須忽略 hostile PATH 並只執行絕對工具'
fi
assert_no_uid_or_raw_response 'hostile PATH 隔離'

for imported_function in env python3; do
    run_helper_with_imported_function "$imported_function"
    status=$?
    if [ "$status" -eq 2 ] && \
       [ ! -s "$HOSTILE_SENTINEL" ] && \
       [ ! -s "$STUB_LOG" ] && \
       [ ! -s "$STUB_STDIN_LOG" ]; then
        pass
    else
        fail "imported $imported_function Bash function 必須在 transport 前拒絕"
    fi
    assert_no_uid_or_raw_response "imported $imported_function function 拒絕"
done

run_helper "$SESSION_UID\n" 23 \
    --project susugigi-qa \
    --session-uid-stdin
status=$?
if [ "$status" -ne 0 ]; then
    pass
else
    fail 'delete transport 非零 exit 必須 fail-closed'
fi
assert_no_uid_or_raw_response 'delete transport 非零 exit'

printf '%s\n' "cleanup_qa_fixtures tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
