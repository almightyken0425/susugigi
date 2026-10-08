#!/bin/bash

qa_runtime_monotonic() {
  /usr/bin/python3 -I -c 'import time; print(time.clock_gettime(time.CLOCK_MONOTONIC_RAW))'
}

qa_launch_app_with_marker_stream() {
  local qa_session_token="$1"
  shift
  set +x
  [[ "$qa_session_token" =~ ^[0-9a-f]{64}$ ]] || return 1
  [ "$QA_BUNDLE_ID" = com.almightyken0425.susugigiapp.qa ] || return 1
  [ -n "${METRO_FILTER_PID:-}" ] \
    && kill -0 "$METRO_FILTER_PID" 2>/dev/null \
    || return 1
  [ -n "${METRO_STREAM_FIFO:-}" ] \
    && [ -p "$METRO_STREAM_FIFO" ] \
    && [ ! -L "$METRO_STREAM_FIFO" ] \
    || return 1
  stop_qa_app_console_capture_with_deadline || return 1
  local -a qa_storekit_environment=()
  if [ "${QA_CURRENT_SCENE_ID:-}" = R15 ]; then
    [[ "${QA_LOCAL_STOREKIT_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || return 1
    [ -n "${QA_LOCAL_STOREKIT_FRAMEWORK_PATH:-}" ] && [ -n "${QA_LOCAL_STOREKIT_LIBRARY_PATH:-}" ] || return 1
    qa_storekit_environment=(
      "SIMCTL_CHILD_SUSUGIGI_QA_STOREKIT_SHA256=$QA_LOCAL_STOREKIT_SHA256"
      "SIMCTL_CHILD_DYLD_FRAMEWORK_PATH=$QA_LOCAL_STOREKIT_FRAMEWORK_PATH"
      "SIMCTL_CHILD_DYLD_LIBRARY_PATH=$QA_LOCAL_STOREKIT_LIBRARY_PATH"
    )
  fi
  SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN="$qa_session_token" \
    /usr/bin/env -u SIMCTL_CHILD_SUSUGIGI_QA_STOREKIT_SHA256 \
    -u SIMCTL_CHILD_DYLD_FRAMEWORK_PATH -u SIMCTL_CHILD_DYLD_LIBRARY_PATH "${qa_storekit_environment[@]}" \
    /usr/bin/xcrun simctl launch --console booted "$QA_BUNDLE_ID" "$@" \
      > "$METRO_STREAM_FIFO" 2>&1 &
  QA_APP_CONSOLE_PID=$!
  sleep 0.2
  if ! kill -0 "$QA_APP_CONSOLE_PID" 2>/dev/null; then
    wait "$QA_APP_CONSOLE_PID" 2>/dev/null || true
    QA_APP_CONSOLE_PID=""
    printf '%s\n' QA_APP_CONSOLE_LAUNCH_FAILED >&2
    return 1
  fi
}

qa_runtime_capture_disposal_identity() {
  local qa_expected=null qa_container=""
  [ -z "${READY_IDENTITY_HASH:-}" ] || qa_expected="\"$READY_IDENTITY_HASH\""
  qa_container="$(/usr/bin/xcrun simctl get_app_container booted "$QA_BUNDLE_ID" data 2>/dev/null)" \
    || return 1
  printf '{"token":"%s","expectedIdentity":%s}' "$QA_SESSION_TOKEN" "$qa_expected" \
    | run_session_snapshot_command /usr/bin/python3 -I \
        "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-phase.py" \
        --phase cleanup --data-container "$qa_container"
}

qa_runtime_require_operation_proof() {
  local qa_identity=""
  qa_identity="$(printf '{"token":"%s","expectedIdentity":"%s"}' \
    "$QA_SESSION_TOKEN" "$READY_IDENTITY_HASH" \
    | run_session_snapshot_command /usr/bin/python3 -I \
        "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-phase.py" \
        --phase authorize --data-container "$QA_DATA_CONTAINER")" || return 1
  [ "$qa_identity" = "$READY_IDENTITY_HASH" ]
}

qa_runtime_selection() {
  run_session_snapshot_command /usr/bin/python3 -I \
    "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-selection.py" \
    --payload "$QA_SESSION_PAYLOAD" --sha256 "$QA_SESSION_PAYLOAD_SHA256" \
    --scene "$QA_CURRENT_SCENE_ID" --case "$QA_CURRENT_CASE_ID" "$@"
}

qa_runtime_select_case() {
  local qa_selection=""
  QA_CURRENT_SCENE_ID="$1"
  QA_CURRENT_CASE_ID="$2"
  qa_selection="$(qa_runtime_selection)" || return 1
  IFS=$'\t' read -r PREPARE_SCENE INSPECT_CHECK <<< "$qa_selection"
  QA_CASE_MARKER_START_OFFSET="$(wc -l < "$READY_MARKER_LOG" | tr -d ' ')" || return 1
}

qa_runtime_check_ready() {
  local qa_phase="$1" qa_request="$2" qa_offset="$3" qa_started="$4"
  local qa_expected=null
  case "$qa_phase" in bootstrap|first-launch) ;; *) qa_expected="\"$READY_IDENTITY_HASH\"" ;; esac
  printf '{"token":"%s","expectedIdentity":%s}' "$QA_SESSION_TOKEN" "$qa_expected" \
    | run_session_snapshot_command /usr/bin/python3 -I \
        "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-phase.py" \
        --phase "$qa_phase" --request-id "$qa_request" --offset "$qa_offset" \
        --started "$qa_started" --markers "$READY_MARKER_LOG" \
        --data-container "$QA_DATA_CONTAINER"
}

qa_runtime_report_native_diagnostics() {
  local qa_offset="$1"
  local qa_diagnostic=""
  local qa_observed=0
  local qa_window=""
  qa_window="$(tail -n "+$((qa_offset + 1))" "$READY_MARKER_LOG" 2>/dev/null)" \
    || return 1
  for qa_diagnostic in \
    'QA NATIVE FIREBASE_CONFIG_VALID' \
    'QA NATIVE REACT_START_RETURNED' \
    'QA NATIVE BUNDLE_URL_UNAVAILABLE' \
    'QA NATIVE BUNDLE_INDEX_QA_LOCALHOST' \
    'QA NATIVE BUNDLE_INDEX_QA_NONCANONICAL' \
    'QA NATIVE MARKER_BRIDGE_CALLED' \
    'QA NATIVE LOCAL_STOREKIT_READY' \
    'QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY' \
    'QA NATIVE AUTH_NETWORK_BLOCKED' \
    'QA NATIVE AUTH_NETWORK_RESTORED'; do
    if printf '%s\n' "$qa_window" | grep -Fqx -- "$qa_diagnostic"; then
      printf '%s\n' "$qa_diagnostic" >&2
      qa_observed=1
    fi
  done
  if [ "$qa_observed" = 0 ]; then
    printf '%s\n' 'QA NATIVE NONE_OBSERVED' >&2
  fi
}

qa_runtime_ready_phase() {
  local qa_phase="$1" qa_request="$2" qa_offset="$3" qa_started="$4"
  local qa_identity="" qa_status=0
  while :; do
    require_runtime_marker_session_clean || return 1
    if qa_identity="$(qa_runtime_check_ready "$qa_phase" "$qa_request" "$qa_offset" "$qa_started")"; then
      break
    else
      qa_status=$?
    fi
    if [ "$qa_status" != 42 ]; then
      qa_runtime_report_native_diagnostics "$qa_offset" || true
      return 1
    fi
    sleep 0.1
  done
  if [ "$qa_phase" = bootstrap ]; then
    /usr/bin/xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || return 1
    stop_qa_app_console_capture_with_deadline || return 1
  fi
  wait_for_runtime_marker_quiet_window "$qa_offset" || return 1
  require_runtime_marker_session_clean || return 1
  qa_identity="$(qa_runtime_check_ready "$qa_phase" "$qa_request" "$qa_offset" "$qa_started")" \
    || return 1
  [[ "$qa_identity" =~ ^[0-9a-f]{64}$ ]] || return 1
  if [ "$qa_phase" = bootstrap ] || [ "$qa_phase" = first-launch ]; then
    READY_IDENTITY_HASH="$qa_identity"
  else
    [ "$qa_identity" = "$READY_IDENTITY_HASH" ] || return 1
    AUTHORIZED_OPERATION_READY_CONFIRMED=1
    AUTH_PROVIDER_POST_AUTH_SETTLED=1
  fi
  IDENTITY_TEARDOWN_CONFIRMED=1
}

run_and_validate_qa_bootstrap() {
  local qa_offset="" qa_started=""
  set +x
  [ "$QA_BUNDLE_ID" = com.almightyken0425.susugigiapp.qa ] || return 1
  [ -z "${QA_SESSION_TOKEN:-}" ] && [ -z "${READY_IDENTITY_HASH:-}" ] || return 1
  require_session_runtime_snapshots_current || return 1
  require_runtime_marker_session_clean || return 1
  QA_SESSION_TOKEN="$(/usr/bin/openssl rand -hex 32)" || return 1
  BOOTSTRAP_REQUEST_ID="bootstrap-$(/usr/bin/openssl rand -hex 16)" || return 1
  [[ "$QA_SESSION_TOKEN" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ "$BOOTSTRAP_REQUEST_ID" =~ ^bootstrap-[0-9a-f]{32}$ ]] || return 1
  QA_DATA_CONTAINER="$(/usr/bin/xcrun simctl get_app_container booted "$QA_BUNDLE_ID" data 2>/dev/null)" \
    || return 1
  /usr/bin/xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
  qa_offset="$(wc -l < "$READY_MARKER_LOG" | tr -d ' ')" || return 1
  IDENTITY_TEARDOWN_POSSIBLE=1
  qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN" \
    --qa-request-id "$BOOTSTRAP_REQUEST_ID" || return 1
  qa_started="$(qa_runtime_monotonic)" || return 1
  qa_runtime_ready_phase bootstrap "$BOOTSTRAP_REQUEST_ID" "$qa_offset" "$qa_started"
}

run_and_validate_qa_first_launch() {
  local qa_offset="" qa_started=""
  [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R14:AU-02 ] || return 1
  [ -z "$QA_SESSION_TOKEN" ] && [ -z "$READY_IDENTITY_HASH" ] || return 1
  require_session_runtime_snapshots_current || return 1
  qa_runtime_selection >/dev/null || return 1
  QA_SESSION_TOKEN="$(/usr/bin/openssl rand -hex 32)" || return 1
  QA_FIRST_LAUNCH_REQUEST="first-launch-$(/usr/bin/openssl rand -hex 16)" || return 1
  QA_DATA_CONTAINER="$(/usr/bin/xcrun simctl get_app_container booted "$QA_BUNDLE_ID" data)" || return 1
  /usr/bin/xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
  qa_offset="$(wc -l < "$READY_MARKER_LOG" | tr -d ' ')" || return 1
  IDENTITY_TEARDOWN_POSSIBLE=1
  qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN" \
    --qa-request-id "$QA_FIRST_LAUNCH_REQUEST" --qa-first-launch true || return 1
  qa_started="$(qa_runtime_monotonic)" || return 1
  printf '%s\n' QA_SESSION_FIRST_LAUNCH_OFFLINE_STARTED
  qa_runtime_ready_phase first-launch "$QA_FIRST_LAUNCH_REQUEST" "$qa_offset" "$qa_started" || return 1
  # Before this acknowledgement, the App may create only its disposable Auth identity.
  # Existing proof-backed disposal owns failures before any application data is written.
  acquire_qa_app_mount_cleanup_ownership open-app || return 1
  [ "$FIXTURE_CLEANUP_REQUIRED" = 1 ] || return 1
  printf '{"token":"%s","expectedIdentity":"%s"}' "$QA_SESSION_TOKEN" "$READY_IDENTITY_HASH" \
    | run_session_snapshot_command /usr/bin/python3 -I \
      "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-first-launch.py" \
      --action release --data-container "$QA_DATA_CONTAINER" --request-id "$QA_FIRST_LAUNCH_REQUEST" || return 1
  qa_started="$(qa_runtime_monotonic)" || return 1
  qa_runtime_ready_phase first-home "$QA_FIRST_LAUNCH_REQUEST" "$qa_offset" "$qa_started" || return 1
  printf '%s\n' QA_SESSION_FIRST_LAUNCH_HOME_READY
}

query_r14_defaults() {
  local qa_signature=""
  qa_signature="$(printf '{"token":"%s","expectedIdentity":"%s"}' "$QA_SESSION_TOKEN" "$READY_IDENTITY_HASH" \
    | run_session_snapshot_command /usr/bin/python3 -I \
      "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-first-launch.py" \
      --action defaults --data-container "$QA_DATA_CONTAINER")" || return 1
  [[ "$qa_signature" =~ ^[0-9a-f]{64}$ ]] || return 1
  if [ "$QA_CURRENT_CHECKPOINT_KEY" = R14:4 ]; then
    QA_R14_DEFAULTS_SIGNATURE="$qa_signature"
  else
    [ -n "${QA_R14_DEFAULTS_SIGNATURE:-}" ] && [ "$qa_signature" = "$QA_R14_DEFAULTS_SIGNATURE" ] || return 1
  fi
  printf '%s\n' QA_R14_DEFAULTS_EXACT_MATCH
}

run_and_validate_qa_open_app_operation() {
  local qa_offset="" qa_started=""
  # Check dependencies before mounting an App that can create cloud fixtures.
  if ! declare -F run_qa_sqlite_local_probe require_r03_initial_backup_markers >/dev/null; then
    printf '%s\n' QA_OPERATION_DEPENDENCY_MISSING >&2
    return 1
  fi
  [ "${IDENTITY_TEARDOWN_CONFIRMED:-0}" = 1 ] || return 1
  require_session_runtime_snapshots_current || return 1
  require_runtime_marker_session_clean || return 1
  qa_runtime_selection >/dev/null || return 1
  qa_runtime_require_operation_proof || return 1
  LAST_OPEN_APP_REQUEST_ID="${OPEN_APP_REQUEST_ID:-}"
  OPEN_APP_REQUEST_ID="open-app-$(/usr/bin/openssl rand -hex 16)" || return 1
  [[ "$OPEN_APP_REQUEST_ID" =~ ^open-app-[0-9a-f]{32}$ ]] || return 1
  [ "$OPEN_APP_REQUEST_ID" != "$LAST_OPEN_APP_REQUEST_ID" ] || return 1
  acquire_qa_app_mount_cleanup_ownership open-app || return 1
  require_qa_fixture_cleanup_binding_before_write || return 1
  /usr/bin/xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
  qa_offset="$(wc -l < "$READY_MARKER_LOG" | tr -d ' ')" || return 1
  AUTHORIZED_OPERATION_READY_CONFIRMED=0
  AUTH_PROVIDER_POST_AUTH_SETTLED=0
  IDENTITY_TEARDOWN_POSSIBLE=1
  qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN" \
    --qa-request-id "$OPEN_APP_REQUEST_ID" --qa-open-app true || return 1
  qa_started="$(qa_runtime_monotonic)" || return 1
  qa_runtime_ready_phase open-app "$OPEN_APP_REQUEST_ID" "$qa_offset" "$qa_started" || return 1
  if [ "${QA_CURRENT_SCENE_ID:-}" = R15 ]; then
    tail -n "+$((qa_offset + 1))" "$READY_MARKER_LOG" \
      | grep -Fqx 'QA NATIVE LOCAL_STOREKIT_READY' || return 1
  fi
}

qa_runtime_operation_check() {
  local qa_check="$1"
  local -a qa_result_timing=()
  if [ "$qa_check" = complete ]; then
    qa_result_timing=(--ready-at "$QA_OPERATION_READY_AT" --ready-elapsed "$QA_OPERATION_READY_ELAPSED")
  fi
  printf '{"token":"%s","expectedIdentity":"%s"}' "$QA_SESSION_TOKEN" "$READY_IDENTITY_HASH" \
    | run_session_snapshot_command /usr/bin/python3 -I \
        "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-phase.py" \
        --phase "$QA_OPERATION" --operation-value "$QA_OPERATION_VALUE" \
        --request-id "$REQUEST_ID" --offset "$QA_OPERATION_MARKER_START_OFFSET" \
        --started "$QA_OPERATION_STARTED" --markers "$READY_MARKER_LOG" \
        --data-container "$QA_DATA_CONTAINER" --check "$qa_check" "${qa_result_timing[@]}"
}

run_and_validate_qa_operation() {
  local qa_identity="" qa_result="" qa_status=0
  [ "${IDENTITY_TEARDOWN_CONFIRMED:-0}" = 1 ] || return 1
  qa_runtime_selection >/dev/null || return 1
  qa_runtime_require_operation_proof || return 1
  case "$QA_OPERATION" in
    prepare) QA_OPERATION_VALUE="$PREPARE_SCENE" ;;
    inspect) QA_OPERATION_VALUE="$INSPECT_CHECK" ;;
    *) return 1 ;;
  esac
  [ "$QA_OPERATION_VALUE" != none ] || return 1
  derive_qa_fixture_write_policy || return 1
  acquire_qa_app_mount_cleanup_ownership "$QA_OPERATION" || return 1
  prepare_r13_fixture_cleanup_binding_if_required || return 1
  require_qa_fixture_cleanup_binding_before_write || return 1
  /usr/bin/xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
  if [ "$QA_OPERATION" = prepare ]; then
    clear_existing_qa_fixtures_before_seed_if_required || return 1
  fi
  REQUEST_ID="$QA_OPERATION-$(/usr/bin/openssl rand -hex 16)" || return 1
  QA_OPERATION_MARKER_START_OFFSET="$(wc -l < "$READY_MARKER_LOG" | tr -d ' ')" || return 1
  if [ "$QA_OPERATION:$INSPECT_CHECK" = inspect:accounting.schedule-backfill ]; then
    QA_R13_INSPECT_MARKER_START_OFFSET="$QA_OPERATION_MARKER_START_OFFSET"
  fi
  AUTHORIZED_OPERATION_READY_CONFIRMED=0
  AUTH_PROVIDER_POST_AUTH_SETTLED=0
  IDENTITY_TEARDOWN_POSSIBLE=1
  qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN" \
    --qa-request-id "$REQUEST_ID" \
    "--qa-$QA_OPERATION" "$QA_OPERATION_VALUE" || return 1
  QA_OPERATION_STARTED="$(qa_runtime_monotonic)" || return 1
  while :; do
    require_runtime_marker_session_clean || return 1
    if qa_identity="$(qa_runtime_operation_check ready)"; then break; else qa_status=$?; fi
    [ "$qa_status" = 42 ] || return 1
    sleep 0.1
  done
  [ "$qa_identity" = "$READY_IDENTITY_HASH" ] || return 1
  QA_OPERATION_READY_AT="$(qa_runtime_monotonic)" || return 1
  QA_OPERATION_READY_ELAPSED="$(/usr/bin/python3 -I -c \
    'import sys; print(float(sys.argv[1]) - float(sys.argv[2]))' \
    "$QA_OPERATION_READY_AT" "$QA_OPERATION_STARTED")" || return 1
  while :; do
    require_runtime_marker_session_clean || return 1
    if qa_result="$(qa_runtime_operation_check complete)"; then break; else qa_status=$?; fi
    [ "$qa_status" = 42 ] || return 1
    sleep 0.1
  done
  /usr/bin/xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || return 1
  stop_qa_app_console_capture_with_deadline || return 1
  wait_for_runtime_marker_quiet_window "$QA_OPERATION_MARKER_START_OFFSET" || return 1
  qa_result="$(qa_runtime_operation_check complete)" || return 1
  case "$QA_OPERATION:$QA_OPERATION_VALUE" in
    prepare:r02_end|prepare:r09_stale_schedule)
      require_locked_quality_scene_prepare "$PREPARE_SCENE" "$qa_result" || return 1
      QA_PREPARE_SCENE="$PREPARE_SCENE"
      if [ "$PREPARE_SCENE" = r09_stale_schedule ]; then
        verify_r13_prepared_sqlite_identity || return 1
      fi
      ;;
    inspect:accounting.fixture-summary)
      require_locked_quality_scene_result "$QA_PREPARE_SCENE" "$qa_result" || return 1 ;;
    inspect:accounting.schedule-backfill)
      evaluate_locked_quality_r13_candidate_result "$qa_result" || return 1 ;;
  esac
  AUTHORIZED_OPERATION_READY_CONFIRMED=1
  AUTH_PROVIDER_POST_AUTH_SETTLED=1
  require_runtime_marker_session_clean
}

qa_runtime_probe_checkpoint() {
  QA_CURRENT_CHECKPOINT_KEY="$1"
  qa_runtime_selection --checkpoint "$QA_CURRENT_CHECKPOINT_KEY" >/dev/null || return 1
  [ "$AUTHORIZED_OPERATION_READY_CONFIRMED" = 1 ] && [ "$AUTH_PROVIDER_POST_AUTH_SETTLED" = 1 ] || return 1
  case "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID:$QA_CURRENT_CHECKPOINT_KEY" in
    R14:AU-02:R14:4|R14:AU-02:R14:5) query_r14_defaults || return 1 ;;
    R08:AS-04:R08:8)
      bind_r08_identity_before_language_capture || return 1
      capture_r08_original_language_before_manual_changes || return 1 ;;
    R13:RC-06:R13:6) query_locked_quality_r13_sqlite_profile || return 1 ;;
    R08:CS-01:R08:15) capture_r08_cs01_updated_at_baseline || return 1 ;;
    *)
      bind_qa_session_uid_from_sqlite || return 1
      if [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R03:CS-02 ]; then
        require_r03_initial_backup_markers "$QA_CASE_MARKER_START_OFFSET" || return 1
      fi
      run_qa_firestore_read || return 1 ;;
  esac
  require_runtime_marker_session_clean
}

qa_session_finish() {
  local qa_status="$1"
  trap - EXIT HUP INT TERM
  cleanup_sim_review || qa_status=1
  [ "${SESSION_FAILED:-0}" = 0 ] || qa_status=1
  unset QA_SESSION_TOKEN READY_IDENTITY_HASH QA_SESSION_UID
  exit "$qa_status"
}

qa_session_command_loop() {
  local qa_command="" qa_read_status=0 qa_last_activity="$SECONDS"
  local qa_verb="" qa_scene="" qa_case=""
  set +x
  trap 'qa_session_finish "$?"' EXIT
  trap 'exit 1' HUP INT TERM
  QA_SESSION_IDLE_TIMEOUT="${QA_SESSION_IDLE_TIMEOUT:-1800}"
  [[ "$QA_SESSION_IDLE_TIMEOUT" =~ ^[0-9]+$ ]] \
    && [ "$QA_SESSION_IDLE_TIMEOUT" -ge 1 ] \
    && [ "$QA_SESSION_IDLE_TIMEOUT" -le 28800 ] || exit 1
  while :; do
    require_runtime_marker_session_clean || exit 1
    if [ "$((SECONDS - qa_last_activity))" -ge "$QA_SESSION_IDLE_TIMEOUT" ]; then
      printf '%s\n' QA_SESSION_IDLE_TIMEOUT >&2
      exit 1
    fi
    qa_command=""
    if qa_command="$(run_session_snapshot_command /usr/bin/python3 -I \
        "$SESSION_CONTROL_PLANE_ROOT/scripts/qa-runtime-input.py")"; then
      qa_last_activity="$SECONDS"
      require_runtime_marker_session_clean || exit 1
      require_session_runtime_snapshots_current || exit 1
      case "$qa_command" in
        case\ R[0-9][0-9]\ [A-Z][A-Z]-[0-9][0-9])
          IFS=' ' read -r qa_verb qa_scene qa_case <<< "$qa_command"
          qa_runtime_select_case "$qa_scene" "$qa_case" || exit 1
          printf '%s\n' QA_SESSION_CASE_SELECTED
          ;;
        open-app|cold-reopen)
          run_and_validate_qa_open_app_operation || exit 1
          printf '%s\n' QA_SESSION_APP_READY
          ;;
        prepare|inspect)
          QA_OPERATION="$qa_command"
          run_and_validate_qa_operation || exit 1
          printf '%s\n' QA_SESSION_OPERATION_VERIFIED
          ;;
        probe\ R[0-9][0-9]:[0-9]|probe\ R[0-9][0-9]:[0-9][0-9])
          qa_runtime_probe_checkpoint "${qa_command#probe }" || exit 1
          printf '%s\n' QA_SESSION_PROBE_VERIFIED
          ;;
        r13-final)
          [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R13:RC-06 ] || exit 1
          require_r13_candidate_sqlite_marker_three_way || exit 1
          printf '%s\n' QA_SESSION_R13_RECONCILED
          ;;
        status|continue) printf '%s\n' QA_SESSION_WAITING ;;
        finish) exit 0 ;;
        abort) exit 1 ;;
        *) printf '%s\n' QA_SESSION_COMMAND_REJECTED >&2; exit 1 ;;
      esac
    else
      qa_read_status=$?
      if [ "$qa_read_status" != 42 ]; then
        printf '%s\n' QA_SESSION_INPUT_CLOSED >&2
        exit 1
      fi
    fi
  done
}
