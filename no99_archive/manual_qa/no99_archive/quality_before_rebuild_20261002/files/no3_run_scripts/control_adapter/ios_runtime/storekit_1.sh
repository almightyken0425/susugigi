QA_LOCAL_STOREKIT_SHA256=""
QA_LOCAL_STOREKIT_FRAMEWORK_PATH=""
QA_LOCAL_STOREKIT_LIBRARY_PATH=""
if [ "${QA_CURRENT_SCENE_ID:-}" = R15 ]; then
  [ "${#QA_SCENE_IDS[@]}" -eq 1 ] && [ "${QA_SCENE_IDS[0]}" = R15 ] || exit 1
  [ "$QA_MODE" = Debug-QA ] || exit 1
  [ "$QA_BUNDLE_ID" = com.almightyken0425.susugigiapp.qa ] || exit 1
  for qa_storekit_file in \
    "$MAIN_REPO/ios/SwishLocal.storekit" \
    "$QA_APP_ARTIFACT/SwishLocal.storekit" \
    "$QA_APP_CONTAINER/SwishLocal.storekit"; do
    [ -f "$qa_storekit_file" ] && [ ! -L "$qa_storekit_file" ] || exit 1
    cmp -s "$MAIN_REPO/ios/SwishLocal.storekit" "$qa_storekit_file" || exit 1
  done
  QA_LOCAL_STOREKIT_SHA256=$(/usr/bin/shasum -a 256 "$MAIN_REPO/ios/SwishLocal.storekit" | /usr/bin/awk '{print $1}')
  [[ "$QA_LOCAL_STOREKIT_SHA256" =~ ^[0-9a-f]{64}$ ]] || exit 1
  qa_storekit_developer_root="$(/usr/bin/xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer"
  [ -f "$qa_storekit_developer_root/Library/Frameworks/XCTest.framework/XCTest" ] || exit 1
  [ -f "$qa_storekit_developer_root/Library/PrivateFrameworks/XCTestCore.framework/XCTestCore" ] || exit 1
  QA_LOCAL_STOREKIT_FRAMEWORK_PATH="$qa_storekit_developer_root/Library/Frameworks:$qa_storekit_developer_root/Library/PrivateFrameworks"
  QA_LOCAL_STOREKIT_LIBRARY_PATH="$qa_storekit_developer_root/usr/lib"
  printf '%s\n' QA_LOCAL_STOREKIT_CONFIGURATION_VERIFIED
fi
