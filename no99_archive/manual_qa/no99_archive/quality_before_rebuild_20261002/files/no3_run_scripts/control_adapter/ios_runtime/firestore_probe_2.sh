if [ "$FIRESTORE_READ_REQUIRED" = 1 ]; then
  if [ "$AUTHORIZED_OPERATION_READY_CONFIRMED" != 1 ] \
    || [ "$AUTH_PROVIDER_POST_AUTH_SETTLED" != 1 ]; then
    run_and_validate_qa_open_app_operation
  fi
  test "$AUTHORIZED_OPERATION_READY_CONFIRMED" = 1
  test "$AUTH_PROVIDER_POST_AUTH_SETTLED" = 1
  if ! bind_qa_session_uid_from_sqlite; then
    printf '%s\n' QA_FIRESTORE_IDENTITY_BINDING_FAILED >&2
    exit 1
  fi
  if [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R03:CS-02 ]; then
    require_r03_initial_backup_markers "$QA_CASE_MARKER_START_OFFSET" || exit 1
  fi
  run_qa_firestore_read
fi
