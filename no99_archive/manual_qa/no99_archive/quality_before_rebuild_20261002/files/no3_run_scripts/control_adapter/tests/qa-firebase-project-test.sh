#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBJECT="$TEST_ROOT/programs/qa-firebase-project.sh"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT INT TERM

PASS=0
FAIL=0
QA_BUNDLE_ID="com.almightyken0425.susugigiapp.qa"
QA_GOOGLE_APP_ID="1:352034825841:ios:40c5c3bcfa630b4a6a1dd0"
QA_FIREBASE_CONFIG_SHA256="8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f"
CANONICAL_API_KEY="qa-canonical-placeholder"
MIXED_API_KEY="mixed-production-placeholder-do-not-print"
WRONG_API_KEY="wrong-placeholder-do-not-print"
FAKE_BIN="$TEST_TMP/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${@: -1}"
if grep -Fq '<string>qa-canonical-placeholder</string>' "$target"; then
  printf '%s  %s\n' '8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f' "$target"
else
  printf '%s  %s\n' 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' "$target"
fi
EOF
chmod +x "$FAKE_BIN/shasum"

write_plist() {
  local target="$1"
  local project_id="$2"
  local bundle_id="$3"
  local google_app_id="$4"
  local api_key="$5"

  cat > "$target" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PROJECT_ID</key>
  <string>$project_id</string>
  <key>BUNDLE_ID</key>
  <string>$bundle_id</string>
  <key>GOOGLE_APP_ID</key>
  <string>$google_app_id</string>
  <key>API_KEY</key>
  <string>$api_key</string>
</dict>
</plist>
EOF
}

run_resolver() {
  local qa_plist="$1"
  local bundle_id="$2"
  local google_app_id="$3"
  local config_sha256="$4"

  cd "$TEST_TMP"
  PATH="$FAKE_BIN:$PATH" bash "$SUBJECT" \
    --qa-plist "$qa_plist" \
    --qa-bundle-id "$bundle_id" \
    --qa-google-app-id "$google_app_id" \
    --qa-firebase-config-sha256 "$config_sha256"
}

expect_success() {
  local name="$1"
  local expected="$2"
  local qa_plist="$3"
  local bundle_id="$4"
  local google_app_id="$5"
  local config_sha256="$6"
  local output

  if output=$(run_resolver "$qa_plist" "$bundle_id" "$google_app_id" "$config_sha256" 2> "$TEST_TMP/stderr"); then
    if [ "$output" = "$expected" ]; then
      PASS=$((PASS + 1))
      return
    fi
  fi

  FAIL=$((FAIL + 1))
  echo "  FAIL $name"
  echo "    expected: $expected"
  echo "    got: ${output:-<command failed>}"
}

expect_failure() {
  local name="$1"
  local expected_error="$2"
  local qa_plist="$3"
  local bundle_id="$4"
  local google_app_id="$5"
  local config_sha256="$6"

  if run_resolver "$qa_plist" "$bundle_id" "$google_app_id" "$config_sha256" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    command unexpectedly succeeded"
  elif grep -Fq "$expected_error" "$TEST_TMP/stderr"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    expected error: $expected_error"
    echo "    got: $(cat "$TEST_TMP/stderr")"
  fi
}

expect_failure_without_secret() {
  local name="$1"
  local qa_plist="$2"
  local secret="$3"

  expect_failure \
    "$name" \
    "QA Firebase config SHA-256 不符" \
    "$qa_plist" \
    "$QA_BUNDLE_ID" \
    "$QA_GOOGLE_APP_ID" \
    "$QA_FIREBASE_CONFIG_SHA256"

  if grep -Fq "$secret" "$TEST_TMP/stdout" "$TEST_TMP/stderr"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL $name 洩漏 API key"
  else
    PASS=$((PASS + 1))
  fi
}

expect_production_option_rejected() {
  local name="$1"

  if bash "$SUBJECT" \
    --qa-plist "$QA_PLIST" \
    --production-plist "$QA_PLIST" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    --qa-google-app-id "$QA_GOOGLE_APP_ID" \
    --qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256" \
    > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    command unexpectedly succeeded"
  else
    local status=$?
    if [ "$status" -eq 2 ] && grep -Fq "usage:" "$TEST_TMP/stderr"; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL $name"
      echo "    expected usage error"
      echo "    got: $(cat "$TEST_TMP/stderr")"
    fi
  fi
}

expect_config_sha256_required() {
  local name="$1"

  if PATH="$FAKE_BIN:$PATH" bash "$SUBJECT" \
    --qa-plist "$QA_PLIST" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    --qa-google-app-id "$QA_GOOGLE_APP_ID" \
    > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    command unexpectedly succeeded"
  else
    local status=$?
    if [ "$status" -eq 2 ] && grep -Fq -- "--qa-firebase-config-sha256" "$TEST_TMP/stderr"; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL $name"
      echo "    expected qa firebase config sha256 usage error"
      echo "    got: $(cat "$TEST_TMP/stderr")"
    fi
  fi
}

expect_google_app_id_required() {
  local name="$1"

  if bash "$SUBJECT" \
    --qa-plist "$QA_PLIST" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    command unexpectedly succeeded"
  else
    local status=$?
    if [ "$status" -eq 2 ] && grep -Fq -- "--qa-google-app-id" "$TEST_TMP/stderr"; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL $name"
      echo "    expected qa google app id usage error"
      echo "    got: $(cat "$TEST_TMP/stderr")"
    fi
  fi
}

QA_PLIST="$TEST_TMP/GoogleService-Info-QA.plist"
EMPTY_PROJECT_PLIST="$TEST_TMP/GoogleService-Info-QA-empty.plist"
WRONG_BUNDLE_PLIST="$TEST_TMP/GoogleService-Info-QA-wrong-bundle.plist"
PRODUCTION_IDENTITY_PLIST="$TEST_TMP/GoogleService-Info-QA-production-identity.plist"
WRONG_QA_PROJECT_PLIST="$TEST_TMP/GoogleService-Info-QA-staging.plist"
EMPTY_APP_ID_PLIST="$TEST_TMP/GoogleService-Info-QA-empty-app-id.plist"
WRONG_APP_ID_PLIST="$TEST_TMP/GoogleService-Info-QA-wrong-app-id.plist"
MIXED_API_KEY_PLIST="$TEST_TMP/GoogleService-Info-QA-mixed-api-key.plist"
WRONG_API_KEY_PLIST="$TEST_TMP/GoogleService-Info-QA-wrong-api-key.plist"
PRODUCTION_SYMLINK_PLIST="$TEST_TMP/GoogleService-Info-QA-production-symlink.plist"
DANGLING_SYMLINK_PLIST="$TEST_TMP/GoogleService-Info-QA-dangling-symlink.plist"

write_plist "$QA_PLIST" "susugigi-qa" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$CANONICAL_API_KEY"
write_plist "$EMPTY_PROJECT_PLIST" "" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$CANONICAL_API_KEY"
write_plist "$WRONG_BUNDLE_PLIST" "susugigi-qa" "com.almightyken0425.susugigiapp" "$QA_GOOGLE_APP_ID" "$CANONICAL_API_KEY"
write_plist "$PRODUCTION_IDENTITY_PLIST" "susugigi-c4fb1" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$CANONICAL_API_KEY"
write_plist "$WRONG_QA_PROJECT_PLIST" "susugigi-staging" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$CANONICAL_API_KEY"
write_plist "$EMPTY_APP_ID_PLIST" "susugigi-qa" "$QA_BUNDLE_ID" "" "$CANONICAL_API_KEY"
write_plist "$WRONG_APP_ID_PLIST" "susugigi-qa" "$QA_BUNDLE_ID" "1:352034825841:ios:wrong" "$CANONICAL_API_KEY"
write_plist "$MIXED_API_KEY_PLIST" "susugigi-qa" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$MIXED_API_KEY"
write_plist "$WRONG_API_KEY_PLIST" "susugigi-qa" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$WRONG_API_KEY"
ln -s "$PRODUCTION_IDENTITY_PLIST" "$PRODUCTION_SYMLINK_PLIST"
ln -s "$TEST_TMP/missing-production.plist" "$DANGLING_SYMLINK_PLIST"

cat > "$TEST_TMP/.firebaserc" <<'EOF'
{
  "projects": {
    "default": "susugigi-c4fb1"
  }
}
EOF

echo "=== QA Firebase project resolver ==="
expect_success ".firebaserc 不得覆蓋 QA plist" "susugigi-qa" "$QA_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "缺 QA plist 時停止" "QA Firebase plist 不存在" "$TEST_TMP/missing.plist" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "QA plist symlink 到 Production 時停止" "QA Firebase plist 不得為 symlink" "$PRODUCTION_SYMLINK_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "dangling QA plist symlink 時停止" "QA Firebase plist 不得為 symlink" "$DANGLING_SYMLINK_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "空 PROJECT_ID 時停止" "QA Firebase PROJECT_ID 為空" "$EMPTY_PROJECT_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "QA project 非 susugigi-qa 時停止" "QA Firebase PROJECT_ID 必須為 susugigi-qa" "$WRONG_QA_PROJECT_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "QA plist 放入 Production identity 時停止" "QA Firebase PROJECT_ID 不得為 Production project" "$PRODUCTION_IDENTITY_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "QA bundle 不符時停止" "QA Firebase BUNDLE_ID 不符" "$WRONG_BUNDLE_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "空 GOOGLE_APP_ID 時停止" "QA Firebase GOOGLE_APP_ID 為空" "$EMPTY_APP_ID_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "plist GOOGLE_APP_ID 不符時停止" "QA Firebase GOOGLE_APP_ID 不符" "$WRONG_APP_ID_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "payload GOOGLE_APP_ID 非 allowlist 時停止" "QA Google app id 必須為 allowlist 值" "$QA_PLIST" "$QA_BUNDLE_ID" "1:352034825841:ios:wrong" "$QA_FIREBASE_CONFIG_SHA256"
expect_failure "payload config SHA-256 非 allowlist 時停止" "QA Firebase config SHA-256 必須為 allowlist 值" "$QA_PLIST" "$QA_BUNDLE_ID" "$QA_GOOGLE_APP_ID" "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
expect_failure_without_secret "混入其他 API key 時停止" "$MIXED_API_KEY_PLIST" "$MIXED_API_KEY"
expect_failure_without_secret "錯誤 API key 時停止" "$WRONG_API_KEY_PLIST" "$WRONG_API_KEY"
expect_google_app_id_required "qa google app id 參數必填"
expect_config_sha256_required "qa firebase config sha256 參數必填"
expect_production_option_rejected "Production plist 參數不屬於公開 seam"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
