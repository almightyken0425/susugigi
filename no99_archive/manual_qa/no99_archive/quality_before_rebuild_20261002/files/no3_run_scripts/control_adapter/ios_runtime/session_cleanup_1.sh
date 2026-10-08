SYNTHETIC_TMP=""
SYNTHETIC_INDEX=""
METRO_PID=""
METRO_FILTER_PID=""
QA_APP_CONSOLE_PID=""
METRO_STREAM_TMP=""
METRO_STREAM_FIFO=""
READY_MARKER_LOG=""
MAIN_REPO=""
MAIN_DETACHED=0
MAIN_RESTORE_REQUIRED=0
MAIN_START_HEAD=""
MAIN_ACTUAL_BRANCH=""
MAIN_ACTUAL_HEAD=""
MAIN_DIRTY=""
MAIN_RESTORE_BLOCKED=0
MAIN_QA_FIREBASE_CONFIG=""
MAIN_QA_FIREBASE_CREATED=0
IDENTITY_TEARDOWN_POSSIBLE=0
IDENTITY_TEARDOWN_CONFIRMED=0
IDENTITY_TEARDOWN_RUNNING=0
IDENTITY_TEARDOWN_ATTEMPTED=0
IDENTITY_TEARDOWN_FAILED=0
IDENTITY_TEARDOWN_FAILURE_REPORTED=0
FIXTURE_CLEANUP_REQUIRED=0
FIXTURE_CLEANUP_CONFIRMED=0
FIXTURE_CLEANUP_ATTEMPTED=0
FIXTURE_CLEANUP_FAILED=0
QA_REMOTE_FIXTURE_WRITE_POSSIBLE=0
QA_FIXTURE_RESEED_REQUIRED=0
QA_FIXTURE_PRESEED_CLEANUP_CONFIRMED=0
SIM_REVIEW_CLEANUP_RUNNING=0
SESSION_FAILED=0
QA_SESSION_TOKEN=""
READY_IDENTITY_HASH=""
QA_SESSION_UID=""
DISPOSE_REQUEST_ID=""
AUTHORIZED_OPERATION_READY_CONFIRMED=0
AUTH_PROVIDER_POST_AUTH_SETTLED=0
QA_R01_USER_BASELINE_SHA256=""
QA_R01_LAST_LOGIN_AT_BASELINE=""
QA_R01_UPDATED_AT_BASELINE=""
QA_R08_ORIGINAL_LANGUAGE=""
QA_R08_CS01_BASELINE_UPDATED_AT=""
QA_PREPARE_RESULT_VALUE_JSON=""
QA_INSPECT_RESULT_VALUE_JSON=""
QA_R13_CANDIDATE_GENERATED_COUNT=""
QA_R13_SQLITE_GENERATED_COUNT=""
QA_R13_INSPECT_MARKER_START_OFFSET=""
LAST_OPEN_APP_REQUEST_ID=""
RUNTIME_MARKER_SESSION_START_OFFSET=0
RUNTIME_MARKER_SESSION_TAINTED=0
SESSION_RUNTIME_ROOT=""
SESSION_CONTROL_PLANE_ROOT=""
SESSION_QUALITY_ROOT=""
SESSION_TRUSTED_SNAPSHOT_VERIFIER=""
SESSION_TRUSTED_VERIFIER_DIGEST=""
SESSION_CONTROL_PLANE_DIGEST=""
SESSION_QUALITY_DIGEST=""
SESSION_RUNTIME_DIGEST=""

session_tree_digest() {
  local qa_session_tree_root="$1"

  [ -d "$qa_session_tree_root" ] \
    && [ ! -L "$qa_session_tree_root" ] \
    || return 1
  qa_firebase_endpoint_safe_env \
    /usr/bin/python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
    --tree-manifest "$qa_session_tree_root"
}

copy_locked_snapshot_files() {
  local qa_snapshot_source="$1"
  local qa_snapshot_destination="$2"
  local qa_snapshot_path_list="$3"
  local qa_snapshot_relative_path=""
  local qa_snapshot_source_path=""
  local qa_snapshot_destination_path=""

  qa_runtime_git -C "$qa_snapshot_source" ls-files \
    --cached --others --exclude-standard -z > "$qa_snapshot_path_list" \
    || return 1
  while IFS= read -r -d '' qa_snapshot_relative_path; do
    case "$qa_snapshot_relative_path" in
      ''|/*|../*|*/../*) return 1 ;;
    esac
    qa_snapshot_source_path="$qa_snapshot_source/$qa_snapshot_relative_path"
    qa_snapshot_destination_path="$qa_snapshot_destination/$qa_snapshot_relative_path"
    [ -e "$qa_snapshot_source_path" ] || [ -L "$qa_snapshot_source_path" ] || continue
    mkdir -p "$(dirname "$qa_snapshot_destination_path")" || return 1
    qa_firebase_endpoint_safe_env \
      /usr/bin/python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
      --copy-regular-file \
      "$qa_snapshot_source_path" "$qa_snapshot_destination_path" \
      || return 1
  done < "$qa_snapshot_path_list"
}

materialize_locked_runtime_root() {
  local qa_snapshot_source="$1"
  local qa_snapshot_destination="$2"
  local qa_snapshot_kind="$3"
  local qa_snapshot_revision="$4"
  local qa_snapshot_repository="$5"
  local qa_snapshot_schema="$6"
  local qa_snapshot_expected_digest="$7"
  local qa_snapshot_path_list="$SESSION_RUNTIME_ROOT/source-paths.$$.bin"
  local qa_snapshot_index_list="$SESSION_RUNTIME_ROOT/source-index.$$.bin"
  local qa_snapshot_actual_digest=""

  if [ "$qa_snapshot_kind" = clean ]; then
    qa_snapshot_expected_digest="$(
      qa_firebase_endpoint_safe_env \
        /usr/bin/python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
        --repo "$qa_snapshot_source" \
        --repository "$qa_snapshot_repository" \
        --schema "$qa_snapshot_schema"
    )" || return 1
  fi
  case "$qa_snapshot_kind" in
    clean|snapshot)
      qa_runtime_git clone --quiet --local --no-hardlinks --no-checkout \
        "$qa_snapshot_source" "$qa_snapshot_destination" \
        || return 1
      qa_runtime_git -C "$qa_snapshot_destination" update-ref \
        refs/heads/qa-session "$qa_snapshot_revision" \
        || return 1
      qa_runtime_git -C "$qa_snapshot_destination" symbolic-ref \
        HEAD refs/heads/qa-session \
        || return 1
      qa_runtime_git -C "$qa_snapshot_source" ls-files --stage -z \
        > "$qa_snapshot_index_list" \
        || return 1
      qa_runtime_git -C "$qa_snapshot_destination" read-tree --empty \
        || return 1
      qa_runtime_git -C "$qa_snapshot_destination" update-index -z --index-info \
        < "$qa_snapshot_index_list" \
        || return 1
      copy_locked_snapshot_files \
        "$qa_snapshot_source" \
        "$qa_snapshot_destination" \
        "$qa_snapshot_path_list" \
        || return 1
      qa_snapshot_actual_digest="$(
        qa_firebase_endpoint_safe_env \
          /usr/bin/python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
          --repo "$qa_snapshot_destination" \
          --repository "$qa_snapshot_repository" \
          --schema "$qa_snapshot_schema"
      )" || return 1
      [ "$qa_snapshot_actual_digest" = "$qa_snapshot_expected_digest" ] \
        || return 1
      /bin/rm -rf "$qa_snapshot_destination/.git" \
        && [ ! -e "$qa_snapshot_destination/.git" ] \
        || return 1
      ;;
    *) return 1 ;;
  esac
  /bin/rm -f "$qa_snapshot_path_list" "$qa_snapshot_index_list"
  [ -z "$(find "$qa_snapshot_destination" -type l -print -quit)" ]
}

require_session_runtime_snapshots_current() {
  local qa_control_digest=""
  local qa_quality_digest=""
  local qa_runtime_digest=""

  [ -d "$SESSION_CONTROL_PLANE_ROOT" ] \
    && [ ! -L "$SESSION_CONTROL_PLANE_ROOT" ] \
    && [ -d "$SESSION_QUALITY_ROOT" ] \
    && [ ! -L "$SESSION_QUALITY_ROOT" ] \
    && [ -f "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" ] \
    && [ ! -L "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" ] \
    && [ ! -w "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" ] \
    && [ -z "$(find "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" -type f -links +1 -print -quit)" ] \
    && [ "$(/usr/bin/shasum -a 256 "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" | /usr/bin/awk '{print $1}')" = "$SESSION_TRUSTED_VERIFIER_DIGEST" ] \
    && [ -z "$(find "$SESSION_RUNTIME_ROOT" -perm -222 -print -quit)" ] \
    || return 1
  qa_control_digest="$(session_tree_digest "$SESSION_CONTROL_PLANE_ROOT")" \
    || return 1
  qa_quality_digest="$(session_tree_digest "$SESSION_QUALITY_ROOT")" \
    || return 1
  qa_runtime_digest="$(session_tree_digest "$SESSION_RUNTIME_ROOT")" \
    || return 1
  [ "$qa_control_digest" = "$SESSION_CONTROL_PLANE_DIGEST" ] \
    && [ "$qa_quality_digest" = "$SESSION_QUALITY_DIGEST" ] \
    && [ "$qa_runtime_digest" = "$SESSION_RUNTIME_DIGEST" ]
}

run_session_snapshot_command() {
  local qa_session_command_status=0

  require_session_runtime_snapshots_current || return 1
  qa_firebase_endpoint_safe_env \
    /usr/bin/python3 -I "$SESSION_CONTROL_PLANE_ROOT/scripts/qa-safe-child-env.py" \
    -- "$@" \
    || qa_session_command_status=$?
  require_session_runtime_snapshots_current || return 1
  return "$qa_session_command_status"
}

materialize_session_runtime_snapshots() {
  local qa_trusted_verifier_blob=""
  local qa_runtime_temp_root=""

  umask 077
  qa_firebase_endpoint_safe_env /usr/bin/true || return 1
  require_trusted_control_plane_identity_current || return 1
  qa_runtime_temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)" \
    || return 1
  SESSION_RUNTIME_ROOT="$(/usr/bin/mktemp -d "$qa_runtime_temp_root/sim-review-runtime.XXXXXX")" \
    || return 1
  SESSION_CONTROL_PLANE_ROOT="$SESSION_RUNTIME_ROOT/control"
  SESSION_QUALITY_ROOT="$SESSION_RUNTIME_ROOT/quality"
  SESSION_TRUSTED_SNAPSHOT_VERIFIER="$SESSION_RUNTIME_ROOT/qa-repo-snapshot.py"
  /usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" show "$TRUSTED_CONTROL_PLANE_COMMIT:scripts/qa-repo-snapshot.py" \
    > "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
    || return 1
  qa_trusted_verifier_blob="$(
    /usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" rev-parse \
      "$TRUSTED_CONTROL_PLANE_COMMIT:scripts/qa-repo-snapshot.py"
  )" || return 1
  [ "$(/usr/bin/git hash-object "$SESSION_TRUSTED_SNAPSHOT_VERIFIER")" = "$qa_trusted_verifier_blob" ] \
    || return 1
  chmod 500 "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" || return 1
  SESSION_TRUSTED_VERIFIER_DIGEST="$(
    /usr/bin/shasum -a 256 "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" | /usr/bin/awk '{print $1}'
  )" || return 1

  require_control_plane_identity_current \
    && require_quality_identity_current \
    || return 1
  case "$CONTROL_PLANE_IDENTITY_KIND" in
    clean)
      materialize_locked_runtime_root \
        "$CONTROL_PLANE_ROOT" "$SESSION_CONTROL_PLANE_ROOT" clean \
        "$CONTROL_PLANE_COMMIT" "$CONTROL_PLANE_REPOSITORY" \
        control-plane-snapshot/v1 '' \
        || return 1
      ;;
    snapshot)
      materialize_locked_runtime_root \
        "$CONTROL_PLANE_ROOT" "$SESSION_CONTROL_PLANE_ROOT" snapshot \
        "$CONTROL_PLANE_BASE_COMMIT" "$CONTROL_PLANE_REPOSITORY" \
        control-plane-snapshot/v1 "$CONTROL_PLANE_SNAPSHOT_DIGEST" \
        || return 1
      ;;
    *) return 1 ;;
  esac
  case "$QUALITY_IDENTITY_KIND" in
    clean)
      materialize_locked_runtime_root \
        "$QUALITY_ROOT" "$SESSION_QUALITY_ROOT" clean \
        "$QUALITY_COMMIT" "$QUALITY_REPOSITORY" \
        quality-snapshot/v1 '' \
        || return 1
      ;;
    snapshot)
      materialize_locked_runtime_root \
        "$QUALITY_ROOT" "$SESSION_QUALITY_ROOT" snapshot \
        "$QUALITY_BASE_COMMIT" "$QUALITY_REPOSITORY" \
        quality-snapshot/v1 "$QUALITY_SNAPSHOT_DIGEST" \
        || return 1
      ;;
    *) return 1 ;;
  esac
  require_control_plane_identity_current \
    && require_quality_identity_current \
    || return 1
  [ -z "$(find "$SESSION_CONTROL_PLANE_ROOT" "$SESSION_QUALITY_ROOT" -type l -print -quit)" ] \
    && [ -z "$(find "$SESSION_CONTROL_PLANE_ROOT" "$SESSION_QUALITY_ROOT" ! -type f ! -type d -print -quit)" ] \
    && [ -z "$(find "$SESSION_CONTROL_PLANE_ROOT" "$SESSION_QUALITY_ROOT" -type f -links +1 -print -quit)" ] \
    || return 1
  QUALITY_FIXTURE_GOLDEN="$SESSION_QUALITY_ROOT/no3_run_scripts/no1_fixture_golden.json"
  [ -f "$QUALITY_FIXTURE_GOLDEN" ] \
    && [ ! -L "$QUALITY_FIXTURE_GOLDEN" ] \
    || return 1
  chmod -R a-w "$SESSION_RUNTIME_ROOT" \
    || return 1
  SESSION_CONTROL_PLANE_DIGEST="$(
    session_tree_digest "$SESSION_CONTROL_PLANE_ROOT"
  )" || return 1
  SESSION_QUALITY_DIGEST="$(
    session_tree_digest "$SESSION_QUALITY_ROOT"
  )" || return 1
  SESSION_RUNTIME_DIGEST="$(
    session_tree_digest "$SESSION_RUNTIME_ROOT"
  )" || return 1
  require_session_runtime_snapshots_current || return 1
  run_session_snapshot_command \
    /usr/bin/python3 -I "$SESSION_CONTROL_PLANE_ROOT/scripts/qa_adapter.py" \
    check --profile susugigi-accounting-ios-v1 \
    --quality-root "$SESSION_QUALITY_ROOT" --snapshot >/dev/null
}

qa_firebase_endpoint_safe_env() {
  local qa_endpoint_name=""
  local qa_blocked_endpoint_name=""
  local -a qa_endpoint_names=(
    FIREBASE_GOOGLE_URL
    FIREBASE_TOKEN_URL
    FIREBASE_AUTH_URL
    FIREBASE_AUTHPROXY_URL
    FIREBASE_AUTH_MANAGEMENT_URL
    FIREBASE_IDENTITY_URL
    FIREBASE_API_URL
    FIREBASE_AUTH_EMULATOR_HOST
    FIRESTORE_EMULATOR_HOST
    FIRESTORE_URL
    FIREBASE_EMULATOR_HUB
    CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE
    CLOUDSDK_AUTH_TOKEN_HOST
    CLOUDSDK_CORE_API_ENDPOINT_OVERRIDES
    CLOUDSDK_PROXY_TYPE
    CLOUDSDK_PROXY_ADDRESS
    CLOUDSDK_PROXY_PORT
    CLOUDSDK_PROXY_USERNAME
    CLOUDSDK_PROXY_PASSWORD
    CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE
    HTTP_PROXY
    HTTPS_PROXY
    ALL_PROXY
    NO_PROXY
    http_proxy
    https_proxy
    all_proxy
    no_proxy
    SSL_CERT_FILE
    SSL_CERT_DIR
    REQUESTS_CA_BUNDLE
    CURL_CA_BUNDLE
    NODE_EXTRA_CA_CERTS
    NODE_TLS_REJECT_UNAUTHORIZED
    npm_config_proxy
    npm_config_https_proxy
    npm_config_cafile
    NPM_CONFIG_USERCONFIG
    PYTHONPATH
    PYTHONHOME
    PYTHONSTARTUP
    PYTHONINSPECT
    PYTHONWARNINGS
    PYTHONBREAKPOINT
    PYTHONUSERBASE
    PYTHONEXECUTABLE
    PYTHONCASEOK
    PYTHONPLATLIBDIR
    PYTHONSAFEPATH
    GRPC_DEFAULT_SSL_ROOTS_FILE_PATH
    GOOGLE_API_USE_MTLS_ENDPOINT
    GOOGLE_API_USE_CLIENT_CERTIFICATE
    FIREBASE_CONFIG
    BASH_ENV
    ENV
    NODE_OPTIONS
    NODE_PATH
    SSLKEYLOGFILE
    DYLD_INSERT_LIBRARIES
    DYLD_LIBRARY_PATH
    LD_PRELOAD
    LD_LIBRARY_PATH
    BASH_XTRACEFD
    PS4
  )
  [ -z "$(builtin export -p -f)" ] || {
    printf '%s\n' QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED >&2
    return 1
  }
  while IFS='=' read -r qa_endpoint_name _; do
    case "$qa_endpoint_name" in
      BASH_FUNC_*|CLOUDSDK_API_ENDPOINT_OVERRIDES_*|FIREBASE_*_URL)
        printf '%s\n' QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED >&2
        return 1
        ;;
    esac
    for qa_blocked_endpoint_name in "${qa_endpoint_names[@]}"; do
      if [ "$qa_endpoint_name" = "$qa_blocked_endpoint_name" ]; then
        printf '%s\n' QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED >&2
        return 1
      fi
    done
  done < <(/usr/bin/env)
  /usr/bin/env \
    -u FIREBASE_GOOGLE_URL \
    -u FIREBASE_TOKEN_URL \
    -u FIREBASE_AUTH_URL \
    -u FIREBASE_AUTHPROXY_URL \
    -u FIREBASE_AUTH_MANAGEMENT_URL \
    -u FIREBASE_IDENTITY_URL \
    -u FIREBASE_API_URL \
    -u FIREBASE_AUTH_EMULATOR_HOST \
    -u FIRESTORE_EMULATOR_HOST \
    -u FIRESTORE_URL \
    -u FIREBASE_EMULATOR_HUB \
    -u CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
    -u CLOUDSDK_AUTH_TOKEN_HOST \
    -u CLOUDSDK_CORE_API_ENDPOINT_OVERRIDES \
    -u CLOUDSDK_PROXY_TYPE \
    -u CLOUDSDK_PROXY_ADDRESS \
    -u CLOUDSDK_PROXY_PORT \
    -u CLOUDSDK_PROXY_USERNAME \
    -u CLOUDSDK_PROXY_PASSWORD \
    -u CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
    -u HTTP_PROXY \
    -u HTTPS_PROXY \
    -u ALL_PROXY \
    -u NO_PROXY \
    -u http_proxy \
    -u https_proxy \
    -u all_proxy \
    -u no_proxy \
    -u SSL_CERT_FILE \
    -u SSL_CERT_DIR \
    -u REQUESTS_CA_BUNDLE \
    -u CURL_CA_BUNDLE \
    -u NODE_EXTRA_CA_CERTS \
    -u NODE_TLS_REJECT_UNAUTHORIZED \
    -u npm_config_proxy \
    -u npm_config_https_proxy \
    -u npm_config_cafile \
    -u NPM_CONFIG_USERCONFIG \
    -u PYTHONPATH \
    -u PYTHONHOME \
    -u PYTHONSTARTUP \
    -u PYTHONINSPECT \
    -u PYTHONWARNINGS \
    -u PYTHONBREAKPOINT \
    -u PYTHONUSERBASE \
    -u PYTHONEXECUTABLE \
    -u PYTHONCASEOK \
    -u PYTHONPLATLIBDIR \
    -u PYTHONSAFEPATH \
    -u GRPC_DEFAULT_SSL_ROOTS_FILE_PATH \
    -u GOOGLE_API_USE_MTLS_ENDPOINT \
    -u GOOGLE_API_USE_CLIENT_CERTIFICATE \
    -u FIREBASE_CONFIG \
    -u BASH_ENV \
    -u ENV \
    -u NODE_OPTIONS \
    -u NODE_PATH \
    -u SSLKEYLOGFILE \
    -u DYLD_INSERT_LIBRARIES \
    -u DYLD_LIBRARY_PATH \
    -u LD_PRELOAD \
    -u LD_LIBRARY_PATH \
    -u BASH_XTRACEFD \
    -u PS4 \
    -u SHELLOPTS \
    -u BASHOPTS \
    PATH="$QA_TRUSTED_SYSTEM_PATH" \
    "$@"
}

derive_qa_fixture_write_policy() {
  local qa_fixture_write_policy=""

  QA_REMOTE_FIXTURE_WRITE_POSSIBLE=0
  QA_FIXTURE_RESEED_REQUIRED=0
  [ "$QA_OPERATION" = prepare ] || return 0
  require_session_runtime_snapshots_current || return 1
  qa_fixture_write_policy="$(
    run_session_snapshot_command \
      /bin/bash "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-fixture-write-policy.sh" \
      --scene "$QA_CURRENT_SCENE_ID" \
      --case "$QA_CURRENT_CASE_ID" \
      --operation "$QA_OPERATION" \
      --seed "$PREPARE_SCENE" 2>/dev/null
  )" || return 1
  case "$qa_fixture_write_policy" in
    'QA_FIXTURE_WRITE_POLICY remote=1 reseed=1')
      QA_REMOTE_FIXTURE_WRITE_POSSIBLE=1
      QA_FIXTURE_RESEED_REQUIRED=1
      ;;
    'QA_FIXTURE_WRITE_POLICY remote=0 reseed=0') ;;
    *) return 1 ;;
  esac
  unset qa_fixture_write_policy
}

run_bound_qa_fixture_cleanup() {
  local qa_fixture_cleanup_tool="$SESSION_QUALITY_ROOT/no2_qa_tools/cleanup_qa_fixtures.sh"
  local qa_cleanup_uid_hash=""
  local qa_cleanup_status=0

  qa_cleanup_uid_hash="$(printf '%s' "$QA_SESSION_UID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  if [ "$QA_FIREBASE_PROJECT_ID" != susugigi-qa ] \
    || [ -z "$QA_SESSION_UID" ] \
    || [ "$qa_cleanup_uid_hash" != "$READY_IDENTITY_HASH" ]; then
    printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=binding reason=invalid' >&2
    return 1
  fi
  if ! require_session_runtime_snapshots_current; then
    printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=snapshot reason=invalid' >&2
    return 1
  fi
  if [ ! -f "$qa_fixture_cleanup_tool" ] \
    || [ -L "$qa_fixture_cleanup_tool" ]; then
    printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=helper reason=unavailable' >&2
    return 1
  fi
  if printf '%s\n' "$QA_SESSION_UID" \
    | run_session_snapshot_command \
        /bin/bash "$qa_fixture_cleanup_tool" \
        --project "$QA_FIREBASE_PROJECT_ID" \
        --session-uid-stdin >/dev/null 2>&1; then
    qa_cleanup_status=0
  else
    qa_cleanup_status=$?
  fi
  # A post-command snapshot failure overrides even a retryable helper status.
  if ! require_session_runtime_snapshots_current; then
    printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=snapshot reason=invalid' >&2
    return 1
  fi
  case "$qa_cleanup_status" in
    0) return 0 ;;
    20) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=credential reason=unavailable' >&2 ;;
    21) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=config reason=unsafe' >&2 ;;
    22) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=scope reason=unexpected' >&2 ;;
    24) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=discovery reason=denied' >&2 ;;
    25) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=delete reason=denied' >&2 ;;
    26) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=discovery reason=failed' >&2 ;;
    27) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=delete reason=failed' >&2 ;;
    75)
      printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=discovery reason=transient' >&2
      return 75 ;;
    76)
      printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=delete reason=transient' >&2
      return 75 ;;
    *) printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=helper reason=unclassified' >&2 ;;
  esac
  return 1
}

verify_qa_fixture_cleanup_absence() {
  local qa_fixture_absence_verdict=""

  qa_fixture_absence_verdict="$(
    qa_firestore_read_driver \
      --project "$QA_FIREBASE_PROJECT_ID" \
      --profile fixture-subtree-absent 2>/dev/null
  )" || {
    printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=absence reason=probe_failed' >&2
    return 1
  }
  if [ "$qa_fixture_absence_verdict" != QA_FIRESTORE_FIXTURE_SUBTREE_ABSENT ]; then
    printf '%s\n' 'QA_FIXTURE_CLEANUP_ERROR phase=absence reason=not_verified' >&2
    return 1
  fi
  return 0
}

cleanup_qa_fixtures_if_required() {
  local qa_cleanup_attempt=0
  local qa_cleanup_attempt_status=1

  [ "$FIXTURE_CLEANUP_REQUIRED" = 1 ] || return 0
  [ "$FIXTURE_CLEANUP_CONFIRMED" = 1 ] && return 0
  [ "$FIXTURE_CLEANUP_ATTEMPTED" = 0 ] || return 1
  FIXTURE_CLEANUP_ATTEMPTED=1
  FIXTURE_CLEANUP_FAILED=1
  while [ "$qa_cleanup_attempt" -lt 3 ]; do
    qa_cleanup_attempt=$((qa_cleanup_attempt + 1))
    if run_bound_qa_fixture_cleanup; then
      if verify_qa_fixture_cleanup_absence; then
        FIXTURE_CLEANUP_CONFIRMED=1
        FIXTURE_CLEANUP_FAILED=0
        printf '%s\n' QA_FIXTURE_CLEANUP_VERIFIED
        return 0
      fi
      break
    else
      qa_cleanup_attempt_status=$?
    fi
    [ "$qa_cleanup_attempt_status" = 75 ] && [ "$qa_cleanup_attempt" -lt 3 ] || break
    printf '%s\n' QA_FIXTURE_CLEANUP_RETRY >&2
    /bin/sleep "$qa_cleanup_attempt" || break
  done
  printf '%s\n' QA_FIXTURE_CLEANUP_FAILED >&2
  printf '%s\n' QA_FIXTURE_RECOVERY_BLOCKED >&2
  return 1
}

stop_marker_filter_with_deadline() {
  local marker_filter_pid="$1"
  local marker_filter_attempt=0
  local marker_filter_state=""

  # The wrapper verifies the immutable runtime again after the filter reaches EOF.
  while [ "$marker_filter_attempt" -lt 100 ]; do
    if ! kill -0 "$marker_filter_pid" 2>/dev/null; then
      if wait "$marker_filter_pid" 2>/dev/null; then
        return 0
      fi
      SESSION_FAILED=1
      printf '%s\n' QA_MARKER_FILTER_FAILED >&2
      return 1
    fi
    marker_filter_state="$(ps -o stat= -p "$marker_filter_pid" 2>/dev/null || true)"
    case "$marker_filter_state" in
      *Z*)
        if wait "$marker_filter_pid" 2>/dev/null; then return 0; fi
        SESSION_FAILED=1
        printf '%s\n' QA_MARKER_FILTER_FAILED >&2
        return 1
        ;;
    esac
    sleep 0.1
    marker_filter_attempt=$((marker_filter_attempt + 1))
  done

  kill "$marker_filter_pid" 2>/dev/null || true
  marker_filter_attempt=0
  while [ "$marker_filter_attempt" -lt 20 ]; do
    if ! kill -0 "$marker_filter_pid" 2>/dev/null; then
      if wait "$marker_filter_pid" 2>/dev/null; then
        return 0
      fi
      SESSION_FAILED=1
      printf '%s\n' QA_MARKER_FILTER_FAILED >&2
      return 1
    fi
    marker_filter_state="$(ps -o stat= -p "$marker_filter_pid" 2>/dev/null || true)"
    case "$marker_filter_state" in
      *Z*)
        if wait "$marker_filter_pid" 2>/dev/null; then return 0; fi
        SESSION_FAILED=1
        printf '%s\n' QA_MARKER_FILTER_FAILED >&2
        return 1
        ;;
    esac
    sleep 0.1
    marker_filter_attempt=$((marker_filter_attempt + 1))
  done

  kill -KILL "$marker_filter_pid" 2>/dev/null || true
  marker_filter_attempt=0
  while [ "$marker_filter_attempt" -lt 20 ]; do
    if ! kill -0 "$marker_filter_pid" 2>/dev/null; then
      if wait "$marker_filter_pid" 2>/dev/null; then
        return 0
      fi
      SESSION_FAILED=1
      printf '%s\n' QA_MARKER_FILTER_FAILED >&2
      return 1
    fi
    marker_filter_state="$(ps -o stat= -p "$marker_filter_pid" 2>/dev/null || true)"
    case "$marker_filter_state" in
      *Z*)
        if wait "$marker_filter_pid" 2>/dev/null; then return 0; fi
        SESSION_FAILED=1
        printf '%s\n' QA_MARKER_FILTER_FAILED >&2
        return 1
        ;;
    esac
    sleep 0.1
    marker_filter_attempt=$((marker_filter_attempt + 1))
  done
  return 1
}

require_marker_filter_running() {
  [ -n "$METRO_FILTER_PID" ] || return 0
  if kill -0 "$METRO_FILTER_PID" 2>/dev/null; then
    return 0
  fi
  wait "$METRO_FILTER_PID" 2>/dev/null || true
  METRO_FILTER_PID=""
  SESSION_FAILED=1
  printf '%s\n' QA_MARKER_FILTER_FAILED >&2
  return 1
}

stop_qa_app_console_capture_with_deadline() {
  local app_console_attempt=0
  local app_console_pid="${QA_APP_CONSOLE_PID:-}"

  [ -n "$app_console_pid" ] || return 0
  if ! [[ "$app_console_pid" =~ ^[1-9][0-9]*$ ]]; then
    SESSION_FAILED=1
    printf '%s\n' QA_APP_CONSOLE_PID_INVALID >&2
    return 1
  fi
  if kill -0 "$app_console_pid" 2>/dev/null; then
    kill "$app_console_pid" 2>/dev/null || true
  fi
  while [ "$app_console_attempt" -lt 20 ]; do
    if ! kill -0 "$app_console_pid" 2>/dev/null; then
      wait "$app_console_pid" 2>/dev/null || true
      QA_APP_CONSOLE_PID=""
      return 0
    fi
    sleep 0.1
    app_console_attempt=$((app_console_attempt + 1))
  done
  kill -KILL "$app_console_pid" 2>/dev/null || true
  wait "$app_console_pid" 2>/dev/null || true
  QA_APP_CONSOLE_PID=""
  if kill -0 "$app_console_pid" 2>/dev/null; then
    SESSION_FAILED=1
    printf '%s\n' QA_APP_CONSOLE_STOP_FAILED >&2
    return 1
  fi
}

wait_for_runtime_marker_quiet_window() {
  local runtime_marker_offset="$1"
  local runtime_marker_sample=0
  local runtime_marker_stable_samples=0
  local runtime_marker_previous_count=-1
  local runtime_marker_current_count=0

  runtime_marker_offset="$(printf '%s' "$runtime_marker_offset" | tr -d '[:space:]')"
  if [ -z "$READY_MARKER_LOG" ] \
    || [ ! -f "$READY_MARKER_LOG" ] \
    || [ -L "$READY_MARKER_LOG" ] \
    || ! [[ "$runtime_marker_offset" =~ ^[0-9]+$ ]]; then
    printf '%s\n' QA_RUNTIME_MARKER_QUIET_WINDOW_PREREQUISITE_FAILED >&2
    return 1
  fi

  while [ "$runtime_marker_sample" -lt 50 ]; do
    require_runtime_marker_session_clean || return 1
    runtime_marker_current_count="$(
      tail -n "+$((runtime_marker_offset + 1))" "$READY_MARKER_LOG" 2>/dev/null \
        | wc -l \
        | tr -d ' '
    )"
    if [ "$runtime_marker_current_count" = "$runtime_marker_previous_count" ]; then
      runtime_marker_stable_samples=$((runtime_marker_stable_samples + 1))
    else
      runtime_marker_previous_count="$runtime_marker_current_count"
      runtime_marker_stable_samples=0
    fi
    if [ "$runtime_marker_stable_samples" -ge 10 ]; then
      return 0
    fi
    sleep 0.1
    runtime_marker_sample=$((runtime_marker_sample + 1))
  done
  printf '%s\n' QA_RUNTIME_MARKER_QUIET_WINDOW_TIMEOUT >&2
  return 1
}

require_runtime_marker_session_clean() {
  local runtime_marker_session_window=""
  local runtime_marker_session_offset=""

  if ! require_marker_filter_running; then
    return 1
  fi
  if [ "$RUNTIME_MARKER_SESSION_TAINTED" = 1 ]; then
    SESSION_FAILED=1
    printf '%s\n' QA_RUNTIME_MARKER_SESSION_TAINTED >&2
    return 1
  fi
  runtime_marker_session_offset="$(
    printf '%s' "$RUNTIME_MARKER_SESSION_START_OFFSET" | tr -d '[:space:]'
  )"
  if [ -z "$READY_MARKER_LOG" ] \
    || [ ! -f "$READY_MARKER_LOG" ] \
    || [ -L "$READY_MARKER_LOG" ] \
    || ! [[ "$runtime_marker_session_offset" =~ ^[0-9]+$ ]]; then
    SESSION_FAILED=1
    printf '%s\n' QA_RUNTIME_MARKER_SESSION_PREREQUISITE_FAILED >&2
    return 1
  fi

  runtime_marker_session_window="$(
    tail -n "+$((runtime_marker_session_offset + 1))" \
      "$READY_MARKER_LOG" 2>/dev/null || true
  )"
  if printf '%s\n' "$runtime_marker_session_window" \
    | grep -Fqx -- 'QA RUNTIME MARKER REJECTED'; then
    RUNTIME_MARKER_SESSION_TAINTED=1
    SESSION_FAILED=1
    printf '%s\n' QA_RUNTIME_MARKER_SESSION_TAINTED >&2
    return 1
  fi
  return 0
}

require_runtime_marker_window_clean() {
  local runtime_marker_window="$1"

  if printf '%s\n' "$runtime_marker_window" \
    | grep -Fqx -- 'QA RUNTIME MARKER REJECTED'; then
    RUNTIME_MARKER_SESSION_TAINTED=1
  fi
  require_runtime_marker_session_clean
}

run_and_validate_qa_identity_disposal() {
  local auth_absence_verdict=""
  local disposal_identity_hash=""
  local dispose_expected_line=""
  local dispose_log_window=""
  local dispose_related_count=0
  local dispose_exact_count=0

  if [ -z "$QA_BUNDLE_ID" ] \
    || [ -z "$QA_SESSION_TOKEN" ] \
    || ! [[ "$QA_SESSION_TOKEN" =~ ^[0-9a-f]{64}$ ]] \
    || [ -z "$READY_MARKER_LOG" ] \
    || [ ! -f "$READY_MARKER_LOG" ] \
    || [ -L "$READY_MARKER_LOG" ]; then
    printf '%s\n' QA_IDENTITY_DISPOSAL_PREREQUISITE_FAILED >&2
    return 1
  fi

  DISPOSE_REQUEST_ID="dispose-$(openssl rand -hex 16)"
  if ! [[ "$DISPOSE_REQUEST_ID" =~ ^dispose-[0-9a-f]{32}$ ]]; then
    printf '%s\n' QA_IDENTITY_DISPOSAL_REQUEST_ID_FAILED >&2
    return 1
  fi
  DISPOSE_LOG_OFFSET="$(wc -l < "$READY_MARKER_LOG")"
  disposal_identity_hash="$(qa_runtime_capture_disposal_identity)" || return 1
  [[ "$disposal_identity_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  dispose_expected_line="QA RESULT {\"schema\":\"qa.runtime/v1\",\"requestId\":\"$DISPOSE_REQUEST_ID\",\"operation\":\"dispose\",\"value\":\"identity\",\"result\":{\"ok\":true,\"value\":{\"identityMode\":\"disposable-anonymous\",\"authDeleted\":true}}}"

  xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
  if ! qa_launch_app_with_marker_stream "$QA_SESSION_TOKEN" \
    --qa-request-id "$DISPOSE_REQUEST_ID" \
    --qa-dispose-identity true; then
    printf '%s\n' QA_IDENTITY_DISPOSAL_LAUNCH_FAILED >&2
    return 1
  fi

  DISPOSE_DEADLINE=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$DISPOSE_DEADLINE" ]; do
    dispose_log_window="$(tail -n "+$((DISPOSE_LOG_OFFSET + 1))" "$READY_MARKER_LOG" 2>/dev/null || true)"
    dispose_related_count="$(
      printf '%s\n' "$dispose_log_window" \
        | grep -F 'QA RESULT ' \
        | grep -Fc -- "\"requestId\":\"$DISPOSE_REQUEST_ID\"" \
        || true
    )"
    if printf '%s\n' "$dispose_log_window" \
      | grep -Fqx -- 'QA RUNTIME MARKER REJECTED' \
      || [ "$dispose_related_count" -gt 0 ]; then
      xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
      if ! stop_qa_app_console_capture_with_deadline; then
        return 1
      fi
      if ! wait_for_runtime_marker_quiet_window "$DISPOSE_LOG_OFFSET"; then
        return 1
      fi
      dispose_log_window="$(tail -n "+$((DISPOSE_LOG_OFFSET + 1))" "$READY_MARKER_LOG" 2>/dev/null || true)"
      if ! require_runtime_marker_window_clean "$dispose_log_window"; then
        return 1
      fi
      dispose_related_count="$(
        printf '%s\n' "$dispose_log_window" \
          | grep -F 'QA RESULT ' \
          | grep -Fc -- "\"requestId\":\"$DISPOSE_REQUEST_ID\"" \
          || true
      )"
      if [ "$dispose_related_count" -gt 1 ]; then
        printf '%s\n' QA_IDENTITY_DISPOSAL_RESULT_NOT_EXACT_ONE >&2
        return 1
      fi
      if [ "$dispose_related_count" -eq 1 ]; then
        dispose_exact_count="$(printf '%s\n' "$dispose_log_window" | grep -Fxc -- "$dispose_expected_line" || true)"
        if [ "$dispose_exact_count" -eq 1 ]; then
          if [ "${QA_CURRENT_SCENE_ID:-}" = R15 ] && ! printf '%s\n' "$dispose_log_window" \
              | grep -Fqx 'QA NATIVE LOCAL_STOREKIT_CLEANED'; then
            SESSION_FAILED=1
            printf '%s\n' QA_LOCAL_STOREKIT_CLEANUP_FAILED >&2
          fi
          if ! require_session_runtime_snapshots_current; then
            printf '%s\n' QA_AUTH_ABSENCE_PROBE_FAILED >&2
            return 1
          fi
          auth_absence_verdict="$(
            printf '%s\n' "$disposal_identity_hash" \
              | run_session_snapshot_command \
                  /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-firebase-auth-absence.py" \
                  --project "$QA_FIREBASE_PROJECT_ID" 2>/dev/null
          )" || {
            printf '%s\n' QA_AUTH_ABSENCE_PROBE_FAILED >&2
            return 1
          }
          if [ "$auth_absence_verdict" = QA_AUTH_IDENTITY_ABSENT ]; then
            return 0
          fi
          printf '%s\n' QA_AUTH_ABSENCE_PROBE_FAILED >&2
          return 1
        fi
      fi
      printf '%s\n' QA_IDENTITY_DISPOSAL_RESULT_INVALID >&2
      return 1
    fi
    sleep 0.2
  done
  printf '%s\n' QA_IDENTITY_DISPOSAL_RESULT_TIMEOUT >&2
  return 1
}

report_identity_teardown_failure() {
  SESSION_FAILED=1
  if [ "$IDENTITY_TEARDOWN_FAILURE_REPORTED" = 0 ]; then
    echo "QA anonymous account cleanup failed; account not cleaned or proven absent" >&2
    IDENTITY_TEARDOWN_FAILURE_REPORTED=1
  fi
}

dispose_qa_identity_if_required() {
  local disposal_status=0

  [ "$IDENTITY_TEARDOWN_POSSIBLE" = 1 ] || return 0
  if [ "$IDENTITY_TEARDOWN_RUNNING" = 1 ] || [ "$IDENTITY_TEARDOWN_ATTEMPTED" = 1 ]; then
    if [ "$IDENTITY_TEARDOWN_FAILED" = 1 ]; then
      report_identity_teardown_failure
      return 1
    fi
    return 0
  fi

  IDENTITY_TEARDOWN_RUNNING=1
  IDENTITY_TEARDOWN_ATTEMPTED=1
  IDENTITY_TEARDOWN_FAILED=1
  if run_and_validate_qa_identity_disposal; then
    IDENTITY_TEARDOWN_POSSIBLE=0
    IDENTITY_TEARDOWN_FAILED=0
    printf '%s\n' QA_IDENTITY_DISPOSAL_VERIFIED
  else
    report_identity_teardown_failure
    disposal_status=1
  fi
  IDENTITY_TEARDOWN_RUNNING=0
  return "$disposal_status"
}

remove_main_qa_firebase_config() {
  [ "$MAIN_QA_FIREBASE_CREATED" = 1 ] || return 0
  if [ -n "$MAIN_QA_FIREBASE_CONFIG" ] \
    && /bin/rm -f "$MAIN_QA_FIREBASE_CONFIG" \
    && [ ! -e "$MAIN_QA_FIREBASE_CONFIG" ] \
    && [ ! -L "$MAIN_QA_FIREBASE_CONFIG" ]; then
    MAIN_QA_FIREBASE_CREATED=0
    MAIN_QA_FIREBASE_CONFIG=""
    return 0
  fi
  SESSION_FAILED=1
  MAIN_RESTORE_BLOCKED=1
  printf '%s\n' QA_FIREBASE_PRIVATE_COPY_CLEANUP_FAILED >&2
  return 1
}

cleanup_session_runtime_snapshots() {
  local qa_runtime_parent=""
  local qa_expected_runtime_parent=""

  [ -n "${SESSION_RUNTIME_ROOT:-}" ] || return 0
  qa_runtime_parent="$(cd -P "$(dirname "$SESSION_RUNTIME_ROOT")" 2>/dev/null && pwd -P)" \
    || return 1
  qa_expected_runtime_parent="$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)" \
    || return 1
  case "$(basename "$SESSION_RUNTIME_ROOT")" in
    sim-review-runtime.??????) ;;
    *) return 1 ;;
  esac
  [ "$qa_runtime_parent" = "$qa_expected_runtime_parent" ] \
    && [ -d "$SESSION_RUNTIME_ROOT" ] \
    && [ ! -L "$SESSION_RUNTIME_ROOT" ] \
    || return 1
  chmod -R u+w "$SESSION_RUNTIME_ROOT" || return 1
  /bin/rm -rf "$SESSION_RUNTIME_ROOT" \
    && [ ! -e "$SESSION_RUNTIME_ROOT" ] \
    || return 1
  SESSION_RUNTIME_ROOT=""
  SESSION_CONTROL_PLANE_ROOT=""
  SESSION_QUALITY_ROOT=""
  SESSION_TRUSTED_SNAPSHOT_VERIFIER=""
  SESSION_TRUSTED_VERIFIER_DIGEST=""
  SESSION_CONTROL_PLANE_DIGEST=""
  SESSION_QUALITY_DIGEST=""
  SESSION_RUNTIME_DIGEST=""
  QUALITY_FIXTURE_GOLDEN=""
}

cleanup_sim_review() {
  local cleanup_status=0

  if [ "$SIM_REVIEW_CLEANUP_RUNNING" = 1 ]; then
    return 0
  fi
  SIM_REVIEW_CLEANUP_RUNNING=1
  if ! cleanup_qa_fixtures_if_required; then
    cleanup_status=1
    SESSION_FAILED=1
  fi
  if ! dispose_qa_identity_if_required; then
    cleanup_status=1
  fi
  QA_SESSION_UID=""
  if [ -n "${QA_BUNDLE_ID:-}" ]; then
    xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  if [ -n "${QA_APP_CONSOLE_PID:-}" ] \
    && ! stop_qa_app_console_capture_with_deadline; then
      cleanup_status=1
  fi
  if [ -n "$METRO_PID" ]; then
    kill "$METRO_PID" 2>/dev/null || true
    wait "$METRO_PID" 2>/dev/null || true
    METRO_PID=""
  fi
  if [ -n "${METRO_FILTER_PID:-}" ]; then
    if stop_marker_filter_with_deadline "$METRO_FILTER_PID"; then
      METRO_FILTER_PID=""
    else
      SESSION_FAILED=1
      cleanup_status=1
      printf '%s\n' QA_MARKER_FILTER_STOP_FAILED >&2
    fi
  fi
  if [ -n "${READY_MARKER_LOG:-}" ] \
    && ! require_runtime_marker_session_clean; then
    cleanup_status=1
  fi
  if [ -n "${METRO_STREAM_FIFO:-}" ]; then
    if /bin/rm -f "$METRO_STREAM_FIFO" \
      && [ ! -e "$METRO_STREAM_FIFO" ] \
      && [ ! -L "$METRO_STREAM_FIFO" ]; then
      METRO_STREAM_FIFO=""
    else
      SESSION_FAILED=1
      cleanup_status=1
      printf '%s\n' QA_MARKER_STREAM_CLEANUP_FAILED >&2
    fi
  fi
  if [ -n "${METRO_STREAM_TMP:-}" ]; then
    if /bin/rm -f "$METRO_STREAM_TMP/launch.json" \
      && /bin/rmdir "$METRO_STREAM_TMP" 2>/dev/null \
      && [ ! -e "$METRO_STREAM_TMP" ]; then
      METRO_STREAM_TMP=""
    else
      SESSION_FAILED=1
      cleanup_status=1
      printf '%s\n' QA_MARKER_STREAM_CLEANUP_FAILED >&2
    fi
  fi
  if [ -n "${READY_MARKER_LOG:-}" ]; then
    if /bin/rm -f "$READY_MARKER_LOG" \
      && [ ! -e "$READY_MARKER_LOG" ] \
      && [ ! -L "$READY_MARKER_LOG" ]; then
      READY_MARKER_LOG=""
    else
      SESSION_FAILED=1
      cleanup_status=1
      printf '%s\n' QA_READY_MARKER_LOG_CLEANUP_FAILED >&2
    fi
  fi
  if ! remove_main_qa_firebase_config; then
    cleanup_status=1
  fi
  if [ "$MAIN_RESTORE_REQUIRED" = 1 ] && [ -n "$MAIN_REPO" ]; then
    if [ "$MAIN_QA_FIREBASE_CREATED" = 1 ]; then
      MAIN_RESTORE_BLOCKED=1
      cleanup_status=1
    else
      MAIN_ACTUAL_BRANCH="$(/usr/bin/git -C "$MAIN_REPO" branch --show-current)"
      MAIN_ACTUAL_HEAD="$(/usr/bin/git -C "$MAIN_REPO" rev-parse HEAD)"
    fi
    if [ "$MAIN_QA_FIREBASE_CREATED" = 1 ]; then
      :
    elif [ "$MAIN_ACTUAL_BRANCH" = main ] && [ "$MAIN_ACTUAL_HEAD" = "$MAIN_START_HEAD" ]; then
      MAIN_RESTORE_REQUIRED=0
      MAIN_DETACHED=0
      MAIN_RESTORE_BLOCKED=0
    elif [ -z "$MAIN_ACTUAL_BRANCH" ] \
      && { [ "$MAIN_ACTUAL_HEAD" = "$TARGET_COMMIT" ] || [ "$MAIN_ACTUAL_HEAD" = "$MAIN_START_HEAD" ]; }; then
      MAIN_DIRTY="$(/usr/bin/git -C "$MAIN_REPO" status --porcelain)"
      if [ -n "$MAIN_DIRTY" ]; then
        MAIN_RESTORE_BLOCKED=1
        cleanup_status=1
        echo "main detached working tree is dirty; checkout main blocked; manual recovery required" >&2
      elif /usr/bin/git -C "$MAIN_REPO" checkout main; then
        MAIN_RESTORE_REQUIRED=0
        MAIN_DETACHED=0
        MAIN_RESTORE_BLOCKED=0
      else
        MAIN_RESTORE_BLOCKED=1
        cleanup_status=1
        echo main checkout restore failed >&2
      fi
    else
      MAIN_RESTORE_BLOCKED=1
      cleanup_status=1
      echo "main restore state unexpected; checkout main blocked; manual recovery required" >&2
    fi
  fi
  if [ -n "$SYNTHETIC_INDEX" ]; then
    /bin/rm -f "$SYNTHETIC_INDEX"
  fi
  if [ -n "$SYNTHETIC_TMP" ]; then
    /bin/rmdir "$SYNTHETIC_TMP" 2>/dev/null || true
  fi
  if ! cleanup_session_runtime_snapshots; then
    cleanup_status=1
    SESSION_FAILED=1
    printf '%s\n' QA_SESSION_RUNTIME_SNAPSHOT_CLEANUP_FAILED >&2
  fi
  if [ "$SESSION_FAILED" = 1 ]; then
    cleanup_status=1
  fi
  SIM_REVIEW_CLEANUP_RUNNING=0
  [ "$cleanup_status" = 0 ]
}

finalize_sim_review() {
  local exit_status="$1"

  trap - EXIT HUP INT TERM
  if ! cleanup_sim_review; then
    exit_status=1
  fi
  if [ "$SESSION_FAILED" = 1 ]; then
    exit_status=1
  fi
  exit "$exit_status"
}

trap 'finalize_sim_review "$?"' EXIT
trap 'exit 1' HUP INT TERM
materialize_session_runtime_snapshots || exit 1
