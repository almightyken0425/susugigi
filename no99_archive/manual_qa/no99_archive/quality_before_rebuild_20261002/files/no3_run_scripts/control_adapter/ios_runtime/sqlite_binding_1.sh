test "$QA_BUNDLE_ID" != "com.almightyken0425.susugigiapp"
case "$QA_BUNDLE_ID" in
  *.qa) ;;
  *) echo "QA bundle id required for sqlite-local" >&2; exit 1 ;;
esac

run_qa_sqlite_local_probe() {
  case "${1:-}:$#" in
    path:1|tables:1|assert:1|sql:2) ;;
    *) echo "sqlite-local probe arguments not allowlisted" >&2; return 2 ;;
  esac
  require_session_runtime_snapshots_current || return 1
  run_session_snapshot_command \
    /bin/bash "$SESSION_QUALITY_ROOT/no2_qa_tools/query_local_db.sh" \
    --bundle-id "$QA_BUNDLE_ID" \
    "$@"
}

if [ "${QA_CURRENT_SCENE_ID:-}" != R14 ]; then
  run_qa_sqlite_local_probe path
fi
