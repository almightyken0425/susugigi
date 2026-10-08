QA_MARKER_GOLDEN_FAMILY_ALLOWLIST=(
  "QA ANALYTICS" "QA BACKUP" "QA BOOT" "QA DBQ"
  "QA FINDING" "QA FOCUS" "QA PAYWALL" "QA PREF"
  "QA PREMIUM" "QA QUOTA" "QA RCACHE" "QA RELEASE"
  "QA SCHED" "QA SEED" "QA UNDO" "QA VALID"
)
QA_MARKER_FILTER_ARGS=()
if [ "${QA_CURRENT_SCENE_ID:-}" = R14 ]; then
  [ "${QA_CURRENT_CASE_ID:-}" = AU-02 ] || exit 1
  run_session_snapshot_command /usr/bin/python3 -I \
    "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-runtime-selection.py" \
    --payload "$QA_SESSION_PAYLOAD" --sha256 "$QA_SESSION_PAYLOAD_SHA256" \
    --scene R14 --case AU-02 >/dev/null || exit 1
  QA_MARKER_FILTER_ARGS+=(--allow-first-launch true)
fi
QA_NORMALIZED_LOG_MARKERS=()
QA_NORMALIZED_LOG_MARKER_MODES=()
for qa_log_marker in "${QA_LOG_MARKERS[@]}"; do
  qa_marker_family=""
  for qa_allowed_family in "${QA_MARKER_GOLDEN_FAMILY_ALLOWLIST[@]}"; do
    case "$qa_log_marker" in
      "$qa_allowed_family"|"$qa_allowed_family "*)
        qa_marker_family="$qa_allowed_family"
        break
        ;;
    esac
  done
  if [ -z "$qa_marker_family" ]; then
    printf '%s\n' QA_MARKER_FAMILY_NOT_ALLOWLISTED >&2
    exit 1
  fi
  QA_MARKER_FILTER_ARGS+=(--allow-golden-marker "$qa_marker_family")
  require_session_runtime_snapshots_current
  qa_normalized_marker="$(
    run_session_snapshot_command \
      /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py" \
      --normalize-expected-marker "$qa_log_marker" 2>/dev/null
  )" || {
    printf '%s\n' QA_EXPECTED_MARKER_INVALID >&2
    exit 1
  }
  QA_NORMALIZED_LOG_MARKERS+=("$qa_normalized_marker")
  case "$qa_log_marker" in
    *"="*) QA_NORMALIZED_LOG_MARKER_MODES+=(exact) ;;
    *) QA_NORMALIZED_LOG_MARKER_MODES+=(prefix) ;;
  esac
done

validate_selected_qa_markers() {
  local qa_case_marker_offset="$1"
  local qa_expected_index=0
  local qa_expected_marker=""
  local qa_expected_mode=""
  local qa_runtime_marker=""
  local qa_marker_matched=0
  local qa_runtime_index=0
  local qa_next_runtime_index=0
  local -a qa_case_marker_lines=()

  [ -f "$READY_MARKER_LOG" ] && [ ! -L "$READY_MARKER_LOG" ] || return 1
  [[ "$qa_case_marker_offset" =~ ^[0-9]+$ ]] || return 1
  [ "$qa_case_marker_offset" -ge "$RUNTIME_MARKER_SESSION_START_OFFSET" ] || return 1
  require_runtime_marker_session_clean || return 1
  while IFS= read -r qa_runtime_marker; do
    qa_case_marker_lines[${#qa_case_marker_lines[@]}]="$qa_runtime_marker"
  done < <(
    tail -n "+$((qa_case_marker_offset + 1))" "$READY_MARKER_LOG"
  )
  while [ "$qa_expected_index" -lt "${#QA_NORMALIZED_LOG_MARKERS[@]}" ]; do
    qa_expected_marker="${QA_NORMALIZED_LOG_MARKERS[$qa_expected_index]}"
    qa_expected_mode="${QA_NORMALIZED_LOG_MARKER_MODES[$qa_expected_index]}"
    case "$qa_expected_marker" in
      *"sha256:$READY_IDENTITY_HASH"*)
        printf '%s\n' QA_EXPECTED_MARKER_IDENTITY_DIGEST_REJECTED >&2
        return 1
        ;;
    esac
    qa_marker_matched=0
    qa_runtime_index="$qa_next_runtime_index"
    while [ "$qa_runtime_index" -lt "${#qa_case_marker_lines[@]}" ]; do
      qa_runtime_marker="${qa_case_marker_lines[$qa_runtime_index]}"
      case "$qa_expected_mode" in
        exact)
          if [ "$qa_runtime_marker" = "$qa_expected_marker" ]; then
            qa_marker_matched=1
            qa_next_runtime_index=$((qa_runtime_index + 1))
            break
          fi
          ;;
        prefix)
          case "$qa_runtime_marker" in
            "$qa_expected_marker"|"$qa_expected_marker "*)
              qa_marker_matched=1
              qa_next_runtime_index=$((qa_runtime_index + 1))
              break
              ;;
          esac
          ;;
        *) return 1 ;;
      esac
      qa_runtime_index=$((qa_runtime_index + 1))
    done
    if [ "$qa_marker_matched" != 1 ]; then
      printf '%s\n' QA_EXPECTED_MARKER_NOT_FOUND >&2
      return 1
    fi
    qa_expected_index=$((qa_expected_index + 1))
  done
  require_runtime_marker_session_clean
}

require_session_runtime_snapshots_current
if ! run_session_snapshot_command \
  /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py" \
  --scan-source "$MAIN_REPO/src" >/dev/null 2>&1; then
  printf '%s\n' QA_MARKER_SOURCE_FORBIDDEN_IDENTITY_FIELD >&2
  exit 1
fi

cd "$MAIN_REPO"
umask 077
QA_MARKER_TEMP_ROOT="$(cd -P "${TMPDIR:-/tmp}" && pwd -P)"
case "$QA_MARKER_TEMP_ROOT" in
  /*) ;;
  *) printf '%s\n' QA_MARKER_TEMP_ROOT_INVALID >&2; exit 1 ;;
esac
READY_MARKER_LOG="$(/usr/bin/mktemp "$QA_MARKER_TEMP_ROOT/sim-review-ready.log.XXXXXX")"
RUNTIME_MARKER_SESSION_START_OFFSET="$(wc -l < "$READY_MARKER_LOG")"
METRO_STREAM_TMP="$(/usr/bin/mktemp -d "$QA_MARKER_TEMP_ROOT/sim-review-stream.XXXXXX")"
require_session_runtime_snapshots_current
run_session_snapshot_command \
  /usr/bin/python3 -I "$SESSION_CONTROL_PLANE_ROOT/scripts/qa-launch-registry.py" \
  --main-repo "$MAIN_REPO" \
  --commit "$TARGET_COMMIT" \
  --tree "$TARGET_TREE" \
  --runtime-dir "$METRO_STREAM_TMP"
METRO_STREAM_FIFO="$METRO_STREAM_TMP/stdout"
/usr/bin/mkfifo "$METRO_STREAM_FIFO"
require_session_runtime_snapshots_current
run_session_snapshot_command \
  /usr/bin/python3 -I "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-safe-marker-filter.py" \
  "${QA_MARKER_FILTER_ARGS[@]}" \
  < "$METRO_STREAM_FIFO" \
  2>/dev/null \
  > "$READY_MARKER_LOG" &
METRO_FILTER_PID=$!
npx react-native start \
  --port 8081 \
  < /dev/null \
  > "$METRO_STREAM_FIFO" 2>&1 &
METRO_PID=$!
