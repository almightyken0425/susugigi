run_qa_manual_cold_reopen() {
  local qa_previous_open_app_request_id="${OPEN_APP_REQUEST_ID:-}"

  run_and_validate_qa_open_app_operation || return 1
  [[ "$OPEN_APP_REQUEST_ID" =~ ^open-app-[0-9a-f]{32}$ ]] \
    && [ "$OPEN_APP_REQUEST_ID" != "$qa_previous_open_app_request_id" ]
}

if [ "$QA_CURRENT_SCENE_ID" = R08 ] \
  && [ -z "$QA_R08_ORIGINAL_LANGUAGE" ]; then
  bind_r08_identity_before_language_capture || exit 1
  capture_r08_original_language_before_manual_changes || exit 1
fi

case "$QA_CURRENT_SCENE_ID:$QA_MANUAL_OPERATION_KIND" in
  R01:cold-reopen|R02:cold-reopen|R08:cold-reopen|R15:cold-reopen)
    run_qa_manual_cold_reopen || exit 1
    ;;
esac

if [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R08:CS-01 ]; then
  capture_r08_cs01_updated_at_baseline || exit 1
fi
QA_CASE_MARKER_START_OFFSET="$(wc -l < "$READY_MARKER_LOG")"
# 執行目前 case。
validate_selected_qa_markers "$QA_CASE_MARKER_START_OFFSET"
if [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID:$QA_CURRENT_CHECKPOINT_KEY" = \
  R13:RC-06:R13:6 ]; then
  query_locked_quality_r13_sqlite_profile || exit 1
fi
if [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID:$QA_CURRENT_CHECKPOINT_KEY" = \
  R13:RC-06:R13:8 ]; then
  require_r13_candidate_sqlite_marker_three_way || exit 1
fi
