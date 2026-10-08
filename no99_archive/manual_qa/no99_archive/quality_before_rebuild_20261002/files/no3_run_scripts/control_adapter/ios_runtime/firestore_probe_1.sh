require_r03_initial_backup_markers() {
  local qa_marker_offset="$1"
  local qa_r03_marker_window=""

  qa_r03_marker_window="$(
    tail -n "+$((qa_marker_offset + 1))" "$READY_MARKER_LOG" 2>/dev/null
  )" || return 1
  [ "$(printf '%s\n' "$qa_r03_marker_window" \
      | grep -Fxc 'QA BACKUP probe remoteHasData=false reads=1' || true)" -eq 1 ] \
    && [ "$(printf '%s\n' "$qa_r03_marker_window" \
      | grep -Ec '^QA BACKUP mode mode=initial([[:space:]]|$)' || true)" -eq 1 ] \
    && ! printf '%s\n' "$qa_r03_marker_window" \
      | grep -Eq '^QA BACKUP mode mode=(incremental|full_delta)([[:space:]]|$)' \
    && ! printf '%s\n' "$qa_r03_marker_window" \
      | grep -Eq '^QA BACKUP skip reason=cooldown([[:space:]]|$)'
}
