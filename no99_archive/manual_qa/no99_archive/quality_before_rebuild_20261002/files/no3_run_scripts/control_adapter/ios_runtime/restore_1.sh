if ! cleanup_qa_fixtures_if_required; then
  SESSION_FAILED=1
fi
if ! dispose_qa_identity_if_required; then
  SESSION_FAILED=1
fi
QA_SESSION_UID=""
xcrun simctl terminate booted "$QA_BUNDLE_ID" >/dev/null 2>&1 || true
if ! stop_qa_app_console_capture_with_deadline; then
  SESSION_FAILED=1
fi
kill "$METRO_PID" 2>/dev/null || true
wait "$METRO_PID" 2>/dev/null || true
METRO_PID=""
if [ -n "$METRO_FILTER_PID" ]; then
  if stop_marker_filter_with_deadline "$METRO_FILTER_PID"; then
    METRO_FILTER_PID=""
  else
    SESSION_FAILED=1
    printf '%s\n' QA_MARKER_FILTER_STOP_FAILED >&2
  fi
fi
if [ -n "$READY_MARKER_LOG" ] \
  && ! require_runtime_marker_session_clean; then
  SESSION_FAILED=1
fi
if [ -n "$METRO_STREAM_FIFO" ]; then
  if /bin/rm -f "$METRO_STREAM_FIFO" \
    && [ ! -e "$METRO_STREAM_FIFO" ] \
    && [ ! -L "$METRO_STREAM_FIFO" ]; then
    METRO_STREAM_FIFO=""
  else
    SESSION_FAILED=1
    printf '%s\n' QA_MARKER_STREAM_CLEANUP_FAILED >&2
  fi
fi
if [ -n "$METRO_STREAM_TMP" ]; then
  if /bin/rm -f "$METRO_STREAM_TMP/launch.json" \
    && /bin/rmdir "$METRO_STREAM_TMP" 2>/dev/null \
    && [ ! -e "$METRO_STREAM_TMP" ]; then
    METRO_STREAM_TMP=""
  else
    SESSION_FAILED=1
    printf '%s\n' QA_MARKER_STREAM_CLEANUP_FAILED >&2
  fi
fi
if [ -n "$READY_MARKER_LOG" ]; then
  if /bin/rm -f "$READY_MARKER_LOG" \
    && [ ! -e "$READY_MARKER_LOG" ] \
    && [ ! -L "$READY_MARKER_LOG" ]; then
    READY_MARKER_LOG=""
  else
    SESSION_FAILED=1
    printf '%s\n' QA_READY_MARKER_LOG_CLEANUP_FAILED >&2
  fi
fi
if ! remove_main_qa_firebase_config; then
  SESSION_FAILED=1
fi
if [ "$MAIN_QA_FIREBASE_CREATED" = 1 ]; then
  MAIN_RESTORE_BLOCKED=1
elif MAIN_ACTUAL_BRANCH="$(/usr/bin/git -C "$MAIN_REPO" branch --show-current)" \
  && MAIN_ACTUAL_HEAD="$(/usr/bin/git -C "$MAIN_REPO" rev-parse HEAD)" \
  && [ "$MAIN_ACTUAL_BRANCH" = main ] \
  && [ "$MAIN_ACTUAL_HEAD" = "$MAIN_START_HEAD" ]; then
  MAIN_RESTORE_REQUIRED=0
  MAIN_DETACHED=0
  MAIN_RESTORE_BLOCKED=0
elif [ -z "$MAIN_ACTUAL_BRANCH" ] \
  && { [ "$MAIN_ACTUAL_HEAD" = "$TARGET_COMMIT" ] || [ "$MAIN_ACTUAL_HEAD" = "$MAIN_START_HEAD" ]; }; then
  MAIN_DIRTY="$(/usr/bin/git -C "$MAIN_REPO" status --porcelain)"
  if [ -n "$MAIN_DIRTY" ]; then
    MAIN_RESTORE_BLOCKED=1
    echo "main detached working tree is dirty; checkout main blocked; manual recovery required" >&2
  else
    /usr/bin/git -C "$MAIN_REPO" checkout main
    MAIN_DETACHED=0
    MAIN_RESTORE_REQUIRED=0
    MAIN_RESTORE_BLOCKED=0
  fi
else
  MAIN_RESTORE_BLOCKED=1
  echo "main restore state unexpected; checkout main blocked; manual recovery required" >&2
fi
test "$MAIN_RESTORE_BLOCKED" = 0
test "$MAIN_RESTORE_REQUIRED" = 0

if [ "$TARGET_KIND" = "worktree-snapshot" ]; then
  test "$(/usr/bin/git -C "$IMPL_WORKTREE" rev-parse HEAD)" = "$ORIGINAL_HEAD"
  test "$(/usr/bin/git -C "$IMPL_WORKTREE" write-tree)" = "$ORIGINAL_INDEX_TREE"
  test "$CURRENT_WORKTREE_SNAPSHOT_DIGEST" = "$ORIGINAL_WORKTREE_SNAPSHOT_DIGEST"
fi

if [ -n "$SYNTHETIC_INDEX" ]; then
  /bin/rm -f "$SYNTHETIC_INDEX"
  SYNTHETIC_INDEX=""
fi
if [ -n "$SYNTHETIC_TMP" ]; then
  /bin/rmdir "$SYNTHETIC_TMP"
  SYNTHETIC_TMP=""
fi
