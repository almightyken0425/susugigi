DISPOSE_REQUEST_ID="dispose-$(openssl rand -hex 16)"
xcrun simctl terminate booted "$QA_BUNDLE_ID" || true
qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN" \
  --qa-request-id "$DISPOSE_REQUEST_ID" \
  --qa-dispose-identity true
