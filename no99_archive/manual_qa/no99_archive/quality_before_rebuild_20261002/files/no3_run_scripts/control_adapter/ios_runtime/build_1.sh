QA_FIREBASE_SOURCE="$IMPL_WORKTREE/ios/GoogleService-Info-QA.plist"
MAIN_QA_FIREBASE_CONFIG="$MAIN_REPO/ios/GoogleService-Info-QA.plist"

test ! -L "$QA_FIREBASE_SOURCE"
test -f "$QA_FIREBASE_SOURCE"
test ! -e "$MAIN_QA_FIREBASE_CONFIG"
test ! -L "$MAIN_QA_FIREBASE_CONFIG"
MAIN_QA_FIREBASE_CREATED=1

SOURCE_QA_FIREBASE_CONFIG_SHA256=$(
  /usr/bin/shasum -a 256 "$QA_FIREBASE_SOURCE" | /usr/bin/awk '{print $1}'
)
test "$SOURCE_QA_FIREBASE_CONFIG_SHA256" = "$QA_FIREBASE_CONFIG_SHA256"

require_session_runtime_snapshots_current
SOURCE_QA_FIREBASE_PROJECT_ID=$(
  run_session_snapshot_command \
    /bin/bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-project.sh" \
    --qa-plist "$QA_FIREBASE_SOURCE" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    --qa-google-app-id "$QA_GOOGLE_APP_ID" \
    --qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256"
)
test "$SOURCE_QA_FIREBASE_PROJECT_ID" = "$QA_FIREBASE_PROJECT_ID"

/usr/bin/git -C "$MAIN_REPO" check-ignore -q "ios/GoogleService-Info-QA.plist"
install -m 600 "$QA_FIREBASE_SOURCE" "$MAIN_QA_FIREBASE_CONFIG"

require_session_runtime_snapshots_current
RESOLVED_QA_FIREBASE_PROJECT_ID=$(
  run_session_snapshot_command \
    /bin/bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-project.sh" \
    --qa-plist "$MAIN_QA_FIREBASE_CONFIG" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    --qa-google-app-id "$QA_GOOGLE_APP_ID" \
    --qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256"
)
test "$RESOLVED_QA_FIREBASE_PROJECT_ID" = "$QA_FIREBASE_PROJECT_ID"
cmp -s "$QA_FIREBASE_SOURCE" "$MAIN_QA_FIREBASE_CONFIG"
