resolve_qa_firestore_profile() {
  local qa_expected_checkpoint_key=""
  local qa_quality_profile_key=""
  case "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" in
    R01:AU-01) QA_FIRESTORE_PROFILE=r01-user-anonymous; qa_quality_profile_key=r01_anonymous_user; qa_expected_checkpoint_key=R01:11 ;;
    R01:AU-03) QA_FIRESTORE_PROFILE=r01-user-unchanged; qa_quality_profile_key=r01_user_unchanged; qa_expected_checkpoint_key=R01:15 ;;
    R03:CS-02) QA_FIRESTORE_PROFILE=r03-initial-backup; qa_quality_profile_key=r03_initial_backup; qa_expected_checkpoint_key=R03:9 ;;
    R03:CS-03) QA_FIRESTORE_PROFILE=r03-incremental-backup; qa_quality_profile_key=r03_incremental_backup; qa_expected_checkpoint_key=R03:21 ;;
    R08:CS-01) QA_FIRESTORE_PROFILE=r08-preferences; qa_quality_profile_key=r08_preferences; qa_expected_checkpoint_key=R08:21 ;;
    R10:*|R11:*|R12:*) printf '%s\n' QA_BLOCKED_FIRESTORE_PROFILE_REJECTED >&2; return 1 ;;
    *) printf '%s\n' QA_FIRESTORE_PROFILE_UNMAPPED >&2; return 1 ;;
  esac
  if [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R03:CS-03 ]; then
    case "$QA_CURRENT_CHECKPOINT_KEY" in
      R03:24) QA_FIRESTORE_PROFILE=r03-updated-backup; qa_quality_profile_key=r03_updated_backup; qa_expected_checkpoint_key=R03:24 ;;
      R03:27) QA_FIRESTORE_PROFILE=r03-deleted-backup; qa_quality_profile_key=r03_deleted_backup; qa_expected_checkpoint_key=R03:27 ;;
    esac
  fi
  [ "$QA_CURRENT_CHECKPOINT_KEY" = "$qa_expected_checkpoint_key" ] || {
    printf '%s\n' QA_FIRESTORE_CHECKPOINT_MISMATCH >&2
    return 1
  }
  QA_QUALITY_FIRESTORE_PROFILE_KEY="$qa_quality_profile_key"
}

require_locked_quality_firestore_profile() {
  local qa_quality_profile_key="${1:-$QA_QUALITY_FIRESTORE_PROFILE_KEY}"
  local qa_quality_golden_output=""

  case "$qa_quality_profile_key" in
    r01_anonymous_user|r01_user_unchanged|r03_initial_backup|r03_incremental_backup|r03_updated_backup|r03_deleted_backup|r08_preferences_baseline|r08_preferences) ;;
    *) return 1 ;;
  esac
  require_session_runtime_snapshots_current || return 1
  qa_quality_golden_output="$(
    run_session_snapshot_command \
      /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py" \
      --golden "$QUALITY_FIXTURE_GOLDEN" \
      --firestore-profile "$qa_quality_profile_key" 2>/dev/null
  )" || {
    unset qa_quality_profile_key qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  [ "$qa_quality_golden_output" = QA_QUALITY_FIRESTORE_PROFILE_MATCH ] || {
    unset qa_quality_profile_key qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  unset qa_quality_profile_key qa_quality_golden_output
}

require_locked_quality_sqlite_profile() {
  local qa_quality_profile_key="$1"
  local qa_quality_golden_output=""

  case "$qa_quality_profile_key" in
    r08_original_language|r13_schedule_backfill) ;;
    *) return 1 ;;
  esac
  require_session_runtime_snapshots_current || return 1
  qa_quality_golden_output="$(
    run_session_snapshot_command \
      /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py" \
      --golden "$QUALITY_FIXTURE_GOLDEN" \
      --sqlite-profile "$qa_quality_profile_key" 2>/dev/null
  )" || return 1
  [ "$qa_quality_golden_output" = QA_QUALITY_SQLITE_PROFILE_MATCH ] || return 1
  unset qa_quality_profile_key qa_quality_golden_output
}

require_locked_quality_scene_prepare() {
  local qa_scene_id="$1"
  local qa_prepared_value_json="$2"
  local qa_quality_golden_output=""

  case "$qa_scene_id" in r02_end|r09_stale_schedule) ;; *) return 1 ;; esac
  require_session_runtime_snapshots_current || return 1
  qa_quality_golden_output="$(
    printf '%s' "$qa_prepared_value_json" \
      | run_session_snapshot_command \
          /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py" \
          --golden "$QUALITY_FIXTURE_GOLDEN" \
          --scene-prepare "$qa_scene_id" 2>/dev/null
  )" || {
    unset qa_prepared_value_json qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  [ "$qa_quality_golden_output" = QA_QUALITY_SCENE_PREPARE_MATCH ] || {
    unset qa_prepared_value_json qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  unset qa_prepared_value_json qa_quality_golden_output
}

require_locked_quality_scene_result() {
  local qa_scene_id="$1"
  local qa_inspect_value_json="$2"
  local qa_quality_golden_output=""

  case "$qa_scene_id" in r02_end|r09_stale_schedule) ;; *) return 1 ;; esac
  require_session_runtime_snapshots_current || return 1
  qa_quality_golden_output="$(
    printf '%s' "$qa_inspect_value_json" \
      | run_session_snapshot_command \
          /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py" \
          --golden "$QUALITY_FIXTURE_GOLDEN" \
          --scene-result "$qa_scene_id" 2>/dev/null
  )" || {
    unset qa_inspect_value_json qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  [ "$qa_quality_golden_output" = QA_QUALITY_SCENE_RESULT_MATCH ] || {
    unset qa_inspect_value_json qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  unset qa_inspect_value_json qa_quality_golden_output
}

evaluate_locked_quality_r13_candidate_result() {
  local qa_inspect_value_json="$1"
  local qa_quality_golden_output=""

  require_session_runtime_snapshots_current || return 1
  qa_quality_golden_output="$(
    printf '%s' "$qa_inspect_value_json" \
      | run_session_snapshot_command \
          /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py" \
          --golden "$QUALITY_FIXTURE_GOLDEN" \
          --r13-candidate-result r13_schedule_backfill 2>/dev/null
  )" || {
    unset qa_inspect_value_json qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  }
  if [[ "$qa_quality_golden_output" =~ ^QA_QUALITY_R13_CANDIDATE\ generated=([0-9]{1,7})$ ]]; then
    QA_R13_CANDIDATE_GENERATED_COUNT="${BASH_REMATCH[1]}"
  else
    unset qa_inspect_value_json qa_quality_golden_output
    printf '%s\n' QA_QUALITY_GOLDEN_REJECTED >&2
    return 1
  fi
  unset qa_inspect_value_json qa_quality_golden_output
}

query_locked_quality_r13_sqlite_profile() {
  local qa_r13_bound_uid_hash=""
  local qa_r13_sqlite_aggregate=""
  local qa_r13_sqlite_verdict=""

  [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R13:RC-06 ] \
    && [ "$QA_CURRENT_CHECKPOINT_KEY" = R13:6 ] \
    && [ -n "$QA_SESSION_UID" ] \
    && require_session_runtime_snapshots_current \
    || return 1
  qa_r13_bound_uid_hash="$(
    printf '%s' "$QA_SESSION_UID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  )"
  [ "$qa_r13_bound_uid_hash" = "$READY_IDENTITY_HASH" ] || return 1
  qa_r13_sqlite_aggregate="$(
    printf '%s\n' "$QA_SESSION_UID" \
      | run_session_snapshot_command \
          /bin/bash "$SESSION_QUALITY_ROOT/no2_qa_tools/query_local_db.sh" \
          --bundle-id "$QA_BUNDLE_ID" \
          --session-uid-stdin \
          profile r13_schedule_backfill 2>/dev/null
  )" || {
    unset qa_r13_bound_uid_hash qa_r13_sqlite_aggregate
    printf '%s\n' QA_R13_SQLITE_PROFILE_FAILED >&2
    return 1
  }
  qa_r13_sqlite_verdict="$(
    printf '%s' "$qa_r13_sqlite_aggregate" \
      | run_session_snapshot_command \
          /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-quality-golden.py" \
          --golden "$QUALITY_FIXTURE_GOLDEN" \
          --r13-sqlite-result r13_schedule_backfill 2>/dev/null
  )" || {
    unset qa_r13_bound_uid_hash qa_r13_sqlite_aggregate qa_r13_sqlite_verdict
    printf '%s\n' QA_R13_SQLITE_PROFILE_FAILED >&2
    return 1
  }
  if [[ "$qa_r13_sqlite_verdict" =~ ^QA_QUALITY_R13_SQLITE\ generated=([0-9]{1,7})$ ]]; then
    QA_R13_SQLITE_GENERATED_COUNT="${BASH_REMATCH[1]}"
  else
    unset qa_r13_bound_uid_hash qa_r13_sqlite_aggregate qa_r13_sqlite_verdict
    printf '%s\n' QA_R13_SQLITE_PROFILE_FAILED >&2
    return 1
  fi
  unset qa_r13_bound_uid_hash qa_r13_sqlite_aggregate qa_r13_sqlite_verdict
}

require_r13_candidate_sqlite_marker_three_way() {
  local qa_r13_marker_window=""
  local qa_r13_marker_line=""
  local qa_r13_marker_count=0
  local qa_r13_marker_generated_count=""

  [[ "$QA_R13_CANDIDATE_GENERATED_COUNT" =~ ^[0-9]{1,7}$ ]] \
    && [[ "$QA_R13_SQLITE_GENERATED_COUNT" =~ ^[0-9]{1,7}$ ]] \
    && [[ "$QA_R13_INSPECT_MARKER_START_OFFSET" =~ ^[0-9]+$ ]] \
    || return 1
  require_runtime_marker_session_clean || return 1
  qa_r13_marker_window="$(
    tail -n "+$((QA_R13_INSPECT_MARKER_START_OFFSET + 1))" \
      "$READY_MARKER_LOG" 2>/dev/null
  )" || return 1
  while IFS= read -r qa_r13_marker_line; do
    if [[ "$qa_r13_marker_line" =~ ^QA\ SCHED\ backfill\ scheduleId=sha256:[0-9a-f]{64}\ generated=([0-9]{1,7})\ fromMs=[0-9]{1,16}\ toMs=[0-9]{1,16}$ ]]; then
      qa_r13_marker_count=$((qa_r13_marker_count + 1))
      qa_r13_marker_generated_count="${BASH_REMATCH[1]}"
    fi
  done <<< "$qa_r13_marker_window"
  [ "$qa_r13_marker_count" -eq 1 ] \
    && [ "$QA_R13_CANDIDATE_GENERATED_COUNT" = "$QA_R13_SQLITE_GENERATED_COUNT" ] \
    && [ "$QA_R13_SQLITE_GENERATED_COUNT" = "$qa_r13_marker_generated_count" ] \
    || {
      printf '%s\n' QA_R13_THREE_WAY_MISMATCH >&2
      return 1
    }
}

qa_firestore_read_driver() {
  local qa_driver_project=""
  local qa_driver_profile=""
  local qa_driver_expected_sha256=""
  local -a qa_driver_arguments=()

  if { [ "$#" -ne 4 ] && [ "$#" -ne 8 ] && [ "$#" -ne 10 ]; } \
    || [ "$1" != --project ] \
    || [ "$3" != --profile ]; then
    printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2
    return 2
  fi
  qa_driver_project="$2"
  qa_driver_profile="$4"
  [ "$qa_driver_project" = "$QA_FIREBASE_PROJECT_ID" ] \
    && [ "$qa_driver_project" = susugigi-qa ] \
    && [ -n "$QA_SESSION_UID" ] || return 2
  case "$qa_driver_profile" in
    fixture-subtree-absent|r01-user-anonymous|r03-initial-backup|r03-incremental-backup|r03-updated-backup|r03-deleted-backup|r08-preferences-baseline)
      [ "$#" -eq 4 ] || return 2
      ;;
    r01-user-unchanged)
      [ "$#" -eq 10 ] \
        && [ "$5" = --expected-sha256 ] \
        && [[ "$6" =~ ^[0-9a-f]{64}$ ]] \
        && [ "$7" = --minimum-last-login-at ] \
        && [[ "$8" =~ ^[0-9]{13}$ ]] \
        && [ "$9" = --minimum-updated-at ] \
        && [[ "${10}" =~ ^[0-9]{13}$ ]] \
        || return 2
      qa_driver_expected_sha256="$6"
      ;;
    r08-preferences)
      [ "$#" -eq 8 ] \
        && [ "$5" = --expected-language ] \
        && [[ "$6" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] \
        && [ "$7" = --minimum-updated-at ] \
        && [[ "$8" =~ ^[0-9]{13}$ ]] \
        || return 2
      ;;
    *) printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2; return 2 ;;
  esac
  qa_driver_arguments=(
    --project "$qa_driver_project"
    --profile "$qa_driver_profile"
  )
  if [ -n "$qa_driver_expected_sha256" ]; then
    qa_driver_arguments+=(
      --expected-sha256 "$qa_driver_expected_sha256"
      --minimum-last-login-at "$8"
      --minimum-updated-at "${10}"
    )
  fi
  if [ "$qa_driver_profile" = r08-preferences ]; then
    qa_driver_arguments+=(
      --expected-language "$6"
      --minimum-updated-at "$8"
    )
  fi
  require_session_runtime_snapshots_current || return 1
  printf '%s\n' "$QA_SESSION_UID" \
    | run_session_snapshot_command \
        /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firestore-read.py" \
        "${qa_driver_arguments[@]}"
}

render_qa_firestore_allowlisted_facts_in_memory() {
  case "$1" in
    QA_FIRESTORE_FIXTURE_SUBTREE_ABSENT|QA_FIRESTORE_R01_USER_UNCHANGED|QA_FIRESTORE_R03_INITIAL_BACKUP_MATCH|QA_FIRESTORE_R03_INCREMENTAL_BACKUP_MATCH|QA_FIRESTORE_R03_UPDATED_BACKUP_MATCH|QA_FIRESTORE_R03_DELETED_BACKUP_MATCH|QA_FIRESTORE_R08_PREFERENCES_MATCH)
      printf '%s\n' "$1"
      ;;
    'QA_FIRESTORE_R01_USER_MATCH sha256:'[0-9a-f][0-9a-f]*)
      [[ "$1" =~ ^QA_FIRESTORE_R01_USER_MATCH\ sha256:[0-9a-f]{64}$ ]] || return 1
      printf '%s\n' "$1"
      ;;
    *) return 1 ;;
  esac
}

bind_qa_session_uid_from_sqlite() {
  local qa_sqlite_users_output=""
  local qa_row_number=0
  local qa_candidate_uid=""
  local qa_candidate_hash=""
  local qa_identity_match_count=0
  local qa_matched_uid=""

  # A failed read must not discard the Auth-bound cleanup owner.
  declare -F run_qa_sqlite_local_probe >/dev/null || return 1
  qa_sqlite_users_output="$(
    run_qa_sqlite_local_probe sql \
      "SELECT id FROM users WHERE _status != 'deleted' ORDER BY id;" 2>&1
  )" || {
    unset qa_sqlite_users_output
    return 1
  }

  while IFS= read -r qa_candidate_uid; do
    qa_row_number=$((qa_row_number + 1))
    [ "$qa_row_number" -gt 2 ] || continue
    [ -n "$qa_candidate_uid" ] || continue
    qa_candidate_hash="$(printf '%s' "$qa_candidate_uid" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
    if [ "$qa_candidate_hash" = "$READY_IDENTITY_HASH" ]; then
      qa_identity_match_count=$((qa_identity_match_count + 1))
      qa_matched_uid="$qa_candidate_uid"
    fi
  done <<< "$qa_sqlite_users_output"

  unset qa_sqlite_users_output qa_candidate_uid qa_candidate_hash
  if [ "$qa_identity_match_count" -ne 1 ] || [ -z "$qa_matched_uid" ]; then
    return 1
  fi
  if [ -n "${QA_SESSION_UID:-}" ] && [ "$QA_SESSION_UID" != "$qa_matched_uid" ]; then
    return 1
  fi
  QA_SESSION_UID="$qa_matched_uid"
}

prepare_r13_fixture_cleanup_binding_if_required() {
  [ "$QA_OPERATION" = prepare ] \
    && [ "$PREPARE_SCENE" = r09_stale_schedule ] \
    || return 0
  [ "$FIXTURE_CLEANUP_REQUIRED" = 1 ] \
    && [ -n "$QA_SESSION_UID" ]
}

verify_r13_prepared_sqlite_identity() {
  local qa_r13_auth_bound_uid="$QA_SESSION_UID"
  local qa_r13_auth_bound_hash=""

  [ "$QA_OPERATION" = prepare ] \
    && [ "$PREPARE_SCENE" = r09_stale_schedule ] \
    && [ "$QA_FIXTURE_PRESEED_CLEANUP_CONFIRMED" = 1 ] \
    && [ -n "$qa_r13_auth_bound_uid" ] \
    || return 1
  qa_r13_auth_bound_hash="$(
    printf '%s' "$qa_r13_auth_bound_uid" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  )"
  [ "$qa_r13_auth_bound_hash" = "$READY_IDENTITY_HASH" ] || return 1
  bind_qa_session_uid_from_sqlite || return 1
  [ "$QA_SESSION_UID" = "$qa_r13_auth_bound_uid" ] || {
    QA_SESSION_UID=""
    unset qa_r13_auth_bound_uid qa_r13_auth_bound_hash
    return 1
  }
  unset qa_r13_auth_bound_uid qa_r13_auth_bound_hash
}

bind_qa_session_uid_from_auth_export() {
  local qa_export_bound_uid=""
  local qa_export_bound_hash=""

  if ! [[ "$READY_IDENTITY_HASH" =~ ^[0-9a-f]{64}$ ]] \
    || ! require_session_runtime_snapshots_current; then
    printf '%s\n' QA_AUTH_IDENTITY_BIND_FAILED >&2
    return 1
  fi
  qa_export_bound_uid="$(
    printf '%s\n' "$READY_IDENTITY_HASH" \
      | run_session_snapshot_command \
          /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py" \
          --project "$QA_FIREBASE_PROJECT_ID" \
          --resolve-exact-uid 2>/dev/null
  )" || {
    unset qa_export_bound_uid
    printf '%s\n' QA_AUTH_IDENTITY_BIND_FAILED >&2
    return 1
  }
  if ! [[ "$qa_export_bound_uid" =~ ^[A-Za-z0-9_-]{1,128}$ ]]; then
    unset qa_export_bound_uid
    printf '%s\n' QA_AUTH_IDENTITY_BIND_FAILED >&2
    return 1
  fi
  qa_export_bound_hash="$(printf '%s' "$qa_export_bound_uid" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  if [ "$qa_export_bound_hash" != "$READY_IDENTITY_HASH" ]; then
    unset qa_export_bound_uid qa_export_bound_hash
    printf '%s\n' QA_AUTH_IDENTITY_BIND_FAILED >&2
    return 1
  fi
  QA_SESSION_UID="$qa_export_bound_uid"
  unset qa_export_bound_uid qa_export_bound_hash
}

acquire_qa_app_mount_cleanup_ownership() {
  local qa_mount_operation="$1"
  local qa_mount_uid_hash=""

  case "$qa_mount_operation" in
    open-app|prepare|inspect) ;;
    *) return 1 ;;
  esac
  bind_qa_session_uid_from_auth_export || return 1
  qa_mount_uid_hash="$(
    printf '%s' "$QA_SESSION_UID" \
      | /usr/bin/shasum -a 256 \
      | /usr/bin/awk '{print $1}'
  )" || return 1
  if [ "$qa_mount_uid_hash" != "$READY_IDENTITY_HASH" ]; then
    QA_SESSION_UID=""
    unset qa_mount_uid_hash
    printf '%s\n' QA_FIXTURE_CLEANUP_BINDING_FAILED >&2
    return 1
  fi
  FIXTURE_CLEANUP_REQUIRED=1
  unset qa_mount_uid_hash
}

bind_r08_identity_before_language_capture() {
  local qa_r08_bound_uid_hash=""

  [ "$QA_CURRENT_SCENE_ID" = R08 ] || return 1
  if [ -z "$QA_SESSION_UID" ]; then
    bind_qa_session_uid_from_auth_export || return 1
  fi
  qa_r08_bound_uid_hash="$(
    printf '%s' "$QA_SESSION_UID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  )"
  if [ "$qa_r08_bound_uid_hash" != "$READY_IDENTITY_HASH" ]; then
    unset qa_r08_bound_uid_hash
    printf '%s\n' QA_FIRESTORE_IDENTITY_BINDING_FAILED >&2
    return 1
  fi
  unset qa_r08_bound_uid_hash
}

require_qa_fixture_cleanup_binding_before_write() {
  local qa_bound_uid_hash=""

  if [ "$QA_REMOTE_FIXTURE_WRITE_POSSIBLE" != 1 ] \
    && [ "$QA_FIXTURE_RESEED_REQUIRED" != 1 ]; then
    return 0
  fi
  if [ -z "$QA_SESSION_UID" ] \
    && ! bind_qa_session_uid_from_auth_export; then
    return 1
  fi
  qa_bound_uid_hash="$(printf '%s' "$QA_SESSION_UID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  if [ "$qa_bound_uid_hash" != "$READY_IDENTITY_HASH" ]; then
    unset qa_bound_uid_hash
    printf '%s\n' QA_FIXTURE_CLEANUP_BINDING_FAILED >&2
    return 1
  fi
  unset qa_bound_uid_hash
  FIXTURE_CLEANUP_REQUIRED=1
}

clear_existing_qa_fixtures_before_seed_if_required() {
  [ "$QA_OPERATION" = prepare ] || return 0
  if [ "$QA_REMOTE_FIXTURE_WRITE_POSSIBLE" != 1 ] \
    && [ "$QA_FIXTURE_RESEED_REQUIRED" != 1 ]; then
    return 0
  fi
  [[ "$PREPARE_SCENE" =~ ^[a-z0-9][a-z0-9_]{0,63}$ ]] || {
    printf '%s\n' QA_FIXTURE_PRESEED_CLEANUP_FAILED >&2
    return 1
  }
  QA_FIXTURE_PRESEED_CLEANUP_CONFIRMED=0
  if run_bound_qa_fixture_cleanup \
    && verify_qa_fixture_cleanup_absence; then
    QA_FIXTURE_PRESEED_CLEANUP_CONFIRMED=1
    return 0
  fi
  printf '%s\n' QA_FIXTURE_PRESEED_CLEANUP_FAILED >&2
  return 1
}

capture_r08_original_language_before_manual_changes() {
  local qa_r08_local_output=""
  local qa_r08_bound_uid_hash=""

  [ "$QA_CURRENT_SCENE_ID" = R08 ] \
    && [ "$QA_CURRENT_CHECKPOINT_KEY" = R08:8 ] \
    && [ -z "$QA_R08_ORIGINAL_LANGUAGE" ] \
    && [ -n "$QA_SESSION_UID" ] \
    && require_session_runtime_snapshots_current \
    || return 1
  qa_r08_bound_uid_hash="$(
    printf '%s' "$QA_SESSION_UID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  )"
  [ "$qa_r08_bound_uid_hash" = "$READY_IDENTITY_HASH" ] || return 1
  require_locked_quality_sqlite_profile r08_original_language || return 1
  qa_r08_local_output="$(
    printf '%s\n' "$QA_SESSION_UID" \
      | run_session_snapshot_command \
          /bin/bash "$SESSION_QUALITY_ROOT/no2_qa_tools/query_local_db.sh" \
          --bundle-id "$QA_BUNDLE_ID" \
          --session-uid-stdin \
          profile r08_original_language 2>/dev/null
  )" || return 1
  if [[ "$qa_r08_local_output" =~ ^profile=r08_original_language\ language=([A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*)$ ]]; then
    QA_R08_ORIGINAL_LANGUAGE="${BASH_REMATCH[1]}"
    unset qa_r08_local_output qa_r08_bound_uid_hash
    return 0
  fi
  unset qa_r08_local_output qa_r08_bound_uid_hash
  return 1
}

capture_r08_cs01_updated_at_baseline() {
  local qa_r08_baseline_output=""

  [ "$QA_CURRENT_SCENE_ID:$QA_CURRENT_CASE_ID" = R08:CS-01 ] \
    && [ "$QA_CURRENT_CHECKPOINT_KEY" = R08:15 ] \
    && [[ "$QA_R08_ORIGINAL_LANGUAGE" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] \
    && [ -n "$QA_SESSION_UID" ] \
    || return 1
  require_locked_quality_firestore_profile r08_preferences_baseline || return 1
  qa_r08_baseline_output="$(
    qa_firestore_read_driver \
      --project "$QA_FIREBASE_PROJECT_ID" \
      --profile r08-preferences-baseline 2>/dev/null
  )" || return 1
  if [[ "$qa_r08_baseline_output" =~ ^QA_FIRESTORE_R08_BASELINE\ updatedAt:([0-9]{13})$ ]]; then
    QA_R08_CS01_BASELINE_UPDATED_AT="${BASH_REMATCH[1]}"
    unset qa_r08_baseline_output
    return 0
  fi
  unset qa_r08_baseline_output
  return 1
}

run_qa_firestore_read() {
  local qa_firestore_probe_output=""
  local qa_firestore_visible_output=""
  local -a qa_firestore_driver_arguments=()

  if [ "$#" -ne 0 ] || ! require_runtime_marker_session_clean; then
    printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2
    return 1
  fi
  if [ "$FIRESTORE_READ_REQUIRED" != 1 ] || [ -z "$QA_SESSION_UID" ]; then
    printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2
    return 2
  fi
  resolve_qa_firestore_profile || return 1
  require_locked_quality_firestore_profile || return 1
  qa_firestore_driver_arguments=(
    --project "$QA_FIREBASE_PROJECT_ID"
    --profile "$QA_FIRESTORE_PROFILE"
  )
  if [ "$QA_FIRESTORE_PROFILE" = r01-user-unchanged ]; then
    [[ "$QA_R01_USER_BASELINE_SHA256" =~ ^[0-9a-f]{64}$ ]] \
      && [[ "$QA_R01_LAST_LOGIN_AT_BASELINE" =~ ^[0-9]{13}$ ]] \
      && [[ "$QA_R01_UPDATED_AT_BASELINE" =~ ^[0-9]{13}$ ]] \
      || return 1
    qa_firestore_driver_arguments+=(
      --expected-sha256 "$QA_R01_USER_BASELINE_SHA256"
      --minimum-last-login-at "$QA_R01_LAST_LOGIN_AT_BASELINE"
      --minimum-updated-at "$QA_R01_UPDATED_AT_BASELINE"
    )
  fi
  if [ "$QA_FIRESTORE_PROFILE" = r08-preferences ]; then
    [[ "$QA_R08_ORIGINAL_LANGUAGE" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] \
      && [[ "$QA_R08_CS01_BASELINE_UPDATED_AT" =~ ^[0-9]{13}$ ]] \
      || return 1
    qa_firestore_driver_arguments+=(
      --expected-language "$QA_R08_ORIGINAL_LANGUAGE"
      --minimum-updated-at "$QA_R08_CS01_BASELINE_UPDATED_AT"
    )
  fi

  qa_firestore_probe_output="$(
    qa_firestore_read_driver "${qa_firestore_driver_arguments[@]}" 2>&1
  )" || {
    unset qa_firestore_probe_output qa_firestore_visible_output
    printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2
    return 1
  }

  if [ "$QA_FIRESTORE_PROFILE" = r01-user-anonymous ]; then
    if [[ "$qa_firestore_probe_output" =~ ^QA_FIRESTORE_R01_USER_MATCH\ sha256:([0-9a-f]{64})\ lastLoginAt:([0-9]{13})\ updatedAt:([0-9]{13})$ ]]; then
      QA_R01_USER_BASELINE_SHA256="${BASH_REMATCH[1]}"
      QA_R01_LAST_LOGIN_AT_BASELINE="${BASH_REMATCH[2]}"
      QA_R01_UPDATED_AT_BASELINE="${BASH_REMATCH[3]}"
      qa_firestore_visible_output="QA_FIRESTORE_R01_USER_MATCH sha256:$QA_R01_USER_BASELINE_SHA256"
    else
      unset qa_firestore_probe_output qa_firestore_visible_output
      printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2
      return 1
    fi
  else
    qa_firestore_visible_output="$(
      render_qa_firestore_allowlisted_facts_in_memory "$qa_firestore_probe_output" 2>/dev/null
    )" || {
      unset qa_firestore_probe_output qa_firestore_visible_output
      printf '%s\n' QA_FIRESTORE_PROBE_FAILED >&2
      return 1
    }
  fi
  qa_firestore_visible_output="${qa_firestore_visible_output//"$QA_SESSION_UID"/[QA_SESSION_UID]}"
  printf '%s\n' "$qa_firestore_visible_output"
  unset qa_firestore_probe_output qa_firestore_visible_output
}
