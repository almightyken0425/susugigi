cd "$MAIN_REPO"
QA_XCODE_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_UDID"
QA_APP_DELEGATE_SOURCE="$MAIN_REPO/ios/SuSuGiGiApp/AppDelegate.swift"

verify_qa_app_delegate_compile_guard() {
  local qa_app_delegate_source="$1"
  require_session_runtime_snapshots_current || return 1
  run_session_snapshot_command \
    /usr/bin/python3 -I "$SESSION_CONTROL_PLANE_ROOT/scripts/qa-app-delegate-guard.py" \
    "$qa_app_delegate_source"
}

verify_qa_app_delegate_compile_guard "$QA_APP_DELEGATE_SOURCE"
xcodebuild \
  -workspace ios/SuSuGiGiApp.xcworkspace \
  -scheme "$QA_SCHEME" \
  -configuration "$QA_MODE" \
  -sdk iphonesimulator \
  -destination "$QA_XCODE_DESTINATION" \
  build

QA_BUILD_SETTINGS=$(
  xcodebuild \
    -workspace ios/SuSuGiGiApp.xcworkspace \
    -scheme "$QA_SCHEME" \
    -configuration "$QA_MODE" \
    -sdk iphonesimulator \
    -destination "$QA_XCODE_DESTINATION" \
    -showBuildSettings
)
QA_TARGET_BUILD_DIR=$(
  printf '%s\n' "$QA_BUILD_SETTINGS" \
    | awk -F ' = ' '/ TARGET_BUILD_DIR = / {print $2; exit}'
)
QA_WRAPPER_NAME=$(
  printf '%s\n' "$QA_BUILD_SETTINGS" \
    | awk -F ' = ' '/ WRAPPER_NAME = / {print $2; exit}'
)
QA_SWIFT_CONDITIONS=$(
  printf '%s\n' "$QA_BUILD_SETTINGS" \
    | awk -F ' = ' '/ SWIFT_ACTIVE_COMPILATION_CONDITIONS = / {print $2; exit}'
)
case " $QA_SWIFT_CONDITIONS " in
  *" QA "*) ;;
  *) echo "QA compilation condition missing" >&2; exit 1 ;;
esac

QA_APP_ARTIFACT="$QA_TARGET_BUILD_DIR/$QA_WRAPPER_NAME"
test -d "$QA_APP_ARTIFACT"
QA_ALLOWED_URL_SCHEME="$QA_BUNDLE_ID"
QA_PRODUCTION_URL_SCHEME="com.googleusercontent.apps.515173750154-4fftspgi257ovtom1cf3hrdbaslpr3km"

verify_qa_artifact_url_isolation() {
  local qa_app_path="$1"
  local qa_info_plist="$qa_app_path/Info.plist"
  local qa_url_scheme=""

  qa_url_scheme=$(
    /usr/bin/plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw -o - "$qa_info_plist"
  )
  test "$qa_url_scheme" = "$QA_ALLOWED_URL_SCHEME"
  if /usr/libexec/PlistBuddy \
    -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:1" \
    "$qa_info_plist" >/dev/null 2>&1; then
    echo "QA artifact contains an extra URL scheme" >&2
    return 1
  fi
  if /usr/libexec/PlistBuddy \
    -c "Print :CFBundleURLTypes:1" \
    "$qa_info_plist" >/dev/null 2>&1; then
    echo "QA artifact contains an extra URL route" >&2
    return 1
  fi
  if /usr/bin/plutil -p "$qa_info_plist" \
    | grep -Fq "$QA_PRODUCTION_URL_SCHEME"; then
    echo "QA artifact contains the Production OAuth route" >&2
    return 1
  fi
}

require_session_runtime_snapshots_current
BUILT_QA_FIREBASE_PROJECT_ID=$(
  run_session_snapshot_command \
    /bin/bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-project.sh" \
    --qa-plist "$QA_APP_ARTIFACT/GoogleService-Info.plist" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    --qa-google-app-id "$QA_GOOGLE_APP_ID" \
    --qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256"
)
test "$BUILT_QA_FIREBASE_PROJECT_ID" = "$QA_FIREBASE_PROJECT_ID"
cmp -s "$QA_FIREBASE_SOURCE" "$QA_APP_ARTIFACT/GoogleService-Info.plist"
verify_qa_artifact_url_isolation "$QA_APP_ARTIFACT"

QA_ARTIFACT_BUNDLE_ID="$(
  /usr/bin/plutil -extract CFBundleIdentifier raw -o - "$QA_APP_ARTIFACT/Info.plist"
)"
test "$QA_ARTIFACT_BUNDLE_ID" = "$QA_BUNDLE_ID"

if [ "${QA_CURRENT_SCENE_ID:-}" = R14 ]; then
  [ "${QA_CURRENT_CASE_ID:-}" = AU-02 ] || exit 1
  run_session_snapshot_command /usr/bin/python3 -I \
    "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-selection.py" \
    --payload "$QA_SESSION_PAYLOAD" --sha256 "$QA_SESSION_PAYLOAD_SHA256" \
    --scene R14 --case AU-02 >/dev/null || exit 1
  qa_existing_container="$(xcrun simctl get_app_container booted "$QA_BUNDLE_ID" data 2>/dev/null || true)"
  if [ -n "$qa_existing_container" ]; then
    run_session_snapshot_command /usr/bin/python3 -I \
      "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-first-launch.py" \
      --action reset-check --data-container "$qa_existing_container" || exit 1
    xcrun simctl uninstall booted "$QA_BUNDLE_ID" || exit 1
  fi
  unset qa_existing_container
fi
xcrun simctl install booted "$QA_APP_ARTIFACT"

QA_APP_CONTAINER=$(xcrun simctl get_app_container booted "$QA_BUNDLE_ID" app)
require_session_runtime_snapshots_current
INSTALLED_QA_FIREBASE_PROJECT_ID=$(
  run_session_snapshot_command \
    /bin/bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-project.sh" \
    --qa-plist "$QA_APP_CONTAINER/GoogleService-Info.plist" \
    --qa-bundle-id "$QA_BUNDLE_ID" \
    --qa-google-app-id "$QA_GOOGLE_APP_ID" \
    --qa-firebase-config-sha256 "$QA_FIREBASE_CONFIG_SHA256"
)
test "$INSTALLED_QA_FIREBASE_PROJECT_ID" = "$QA_FIREBASE_PROJECT_ID"
cmp -s "$QA_FIREBASE_SOURCE" "$QA_APP_CONTAINER/GoogleService-Info.plist"
verify_qa_artifact_url_isolation "$QA_APP_CONTAINER"

if ! remove_main_qa_firebase_config; then
  exit 1
fi
