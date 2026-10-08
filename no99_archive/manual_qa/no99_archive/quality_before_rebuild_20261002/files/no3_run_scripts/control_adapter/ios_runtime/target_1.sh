QA_TRUSTED_SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

qa_require_trusted_launcher_shell() {
  local qa_exported_environment=""
  local qa_exported_functions=""

  qa_exported_functions="$(builtin export -p -f)" || return 1
  [ -z "$qa_exported_functions" ] || {
    printf '%s\n' QA_RUNTIME_ENVIRONMENT_REJECTED >&2
    return 1
  }
  qa_exported_environment="$(builtin export -p)" || return 1
  case "$qa_exported_environment" in
    *' BASH_ENV='*|*' ENV='*|*' BASH_XTRACEFD='*|*' PS4='*|\
    *' NODE_OPTIONS='*|*' NODE_PATH='*|*' SSLKEYLOGFILE='*|\
    *' DYLD_INSERT_LIBRARIES='*|*' DYLD_LIBRARY_PATH='*|\
    *' LD_PRELOAD='*|*' LD_LIBRARY_PATH='*)
      printf '%s\n' QA_RUNTIME_ENVIRONMENT_REJECTED >&2
      return 1
      ;;
  esac
  [ "${PATH:-}" = "$QA_TRUSTED_SYSTEM_PATH" ] || {
    printf '%s\n' QA_RUNTIME_ENVIRONMENT_REJECTED >&2
    return 1
  }
  unset qa_exported_environment qa_exported_functions
}

qa_require_trusted_core_tool() {
  local qa_core_tool="$1"
  local qa_core_metadata=""
  local qa_core_mode=""

  [ -f "$qa_core_tool" ] \
    && [ ! -L "$qa_core_tool" ] \
    && [ -x "$qa_core_tool" ] \
    || return 1
  qa_core_metadata="$(/usr/bin/stat -f '%u %Lp' "$qa_core_tool")" \
    || return 1
  [ "${qa_core_metadata%% *}" = 0 ] || return 1
  qa_core_mode="${qa_core_metadata#* }"
  (( (8#$qa_core_mode & 8#22) == 0 ))
}

qa_runtime_git() {
  local -a qa_git_location=()
  local qa_git_filter_status=0
  if [ "${1:-}" = -C ]; then
    [ "$#" -ge 2 ] || return 1
    qa_git_location=(-C "$2" "--work-tree=$2")
    shift 2
  fi
  local -a qa_git_command=(
    /usr/bin/env -i
    PATH="$QA_TRUSTED_SYSTEM_PATH" LC_ALL=C
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1
    GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0
    /usr/bin/git
    -c core.fsmonitor=false -c core.untrackedCache=false
    -c core.hooksPath=/dev/null -c init.templateDir=/dev/null
    -c core.excludesFile=/dev/null -c core.attributesFile=/dev/null
    -c submodule.recurse=false
    "${qa_git_location[@]}"
  )
  if [ "${#qa_git_location[@]}" -gt 0 ]; then
    "${qa_git_command[@]}" config --name-only --get-regexp '^filter\.' \
      >/dev/null 2>&1 || qa_git_filter_status=$?
    [ "$qa_git_filter_status" -eq 1 ] || {
      printf '%s\n' QA_REPO_SOURCE_GIT_CONFIG_REJECTED >&2
      return 1
    }
  fi
  "${qa_git_command[@]}" "$@"
}

qa_require_trusted_launcher_shell || exit 1
for qa_core_tool in \
  /bin/bash \
  /bin/rm \
  /bin/rmdir \
  /usr/bin/env \
  /usr/bin/git \
  /usr/bin/mkfifo \
  /usr/bin/mktemp \
  /usr/bin/plutil \
  /usr/bin/python3 \
  /usr/bin/shasum; do
  qa_require_trusted_core_tool "$qa_core_tool" || exit 1
done
unset qa_core_tool

CONTROL_PLANE_ROOT="$CONTROL_PLANE_WORKTREE_OR_REPO"
TRUSTED_CONTROL_PLANE_ROOT="$TRUSTED_CONTROL_PLANE_ROOT_FROM_PAYLOAD"
QUALITY_ROOT="$QUALITY_WORKTREE_OR_REPO"
QUALITY_REPOSITORY="$QUALITY_IDENTITY_REPOSITORY"
QUALITY_FIXTURE_GOLDEN=""

test -d "$CONTROL_PLANE_ROOT"
test ! -L "$CONTROL_PLANE_ROOT"
test -d "$TRUSTED_CONTROL_PLANE_ROOT"
test ! -L "$TRUSTED_CONTROL_PLANE_ROOT"
test -d "$QUALITY_ROOT"
test ! -L "$QUALITY_ROOT"
test -n "$QUALITY_REPOSITORY"

test "$(cd "$CONTROL_PLANE_ROOT" && pwd -P)" = "$CONTROL_PLANE_ROOT"
test "$(cd "$TRUSTED_CONTROL_PLANE_ROOT" && pwd -P)" = "$TRUSTED_CONTROL_PLANE_ROOT"
test "$(cd "$QUALITY_ROOT" && pwd -P)" = "$QUALITY_ROOT"
test "$(qa_runtime_git -C "$QUALITY_ROOT" remote get-url origin)" = "$QUALITY_REPOSITORY"
test "$TRUSTED_CONTROL_PLANE_ROOT" != "$CONTROL_PLANE_ROOT"

require_trusted_control_plane_identity_current() {
  [ "$TRUSTED_CONTROL_PLANE_IDENTITY_KIND" = clean ] \
    && [ -d "$TRUSTED_CONTROL_PLANE_ROOT" ] \
    && [ ! -L "$TRUSTED_CONTROL_PLANE_ROOT" ] \
    && [ "$(cd "$TRUSTED_CONTROL_PLANE_ROOT" && pwd -P)" = "$TRUSTED_CONTROL_PLANE_ROOT" ] \
    && [ "$TRUSTED_CONTROL_PLANE_ROOT" != "$CONTROL_PLANE_ROOT" ] \
    && [ -z "$(/usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" status --porcelain)" ] \
    && [ "$(/usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" remote get-url origin)" = "$TRUSTED_CONTROL_PLANE_REPOSITORY" ] \
    && [ "$(/usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" rev-parse HEAD^{commit})" = "$TRUSTED_CONTROL_PLANE_COMMIT" ] \
    && [ "$(/usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" rev-parse HEAD^{tree})" = "$TRUSTED_CONTROL_PLANE_TREE" ] \
    && /usr/bin/git -C "$TRUSTED_CONTROL_PLANE_ROOT" cat-file -e \
      "$TRUSTED_CONTROL_PLANE_COMMIT:scripts/qa-repo-snapshot.py"
}

require_control_plane_identity_current() {
  local current_control_plane_snapshot_digest=""

  require_trusted_control_plane_identity_current \
    && [ -d "$CONTROL_PLANE_ROOT" ] \
    && [ ! -L "$CONTROL_PLANE_ROOT" ] \
    && [ "$(cd "$CONTROL_PLANE_ROOT" && pwd -P)" = "$CONTROL_PLANE_ROOT" ] \
    && [ "$(qa_runtime_git -C "$CONTROL_PLANE_ROOT" remote get-url origin)" = "$CONTROL_PLANE_REPOSITORY" ] \
    || return 1
  case "$CONTROL_PLANE_IDENTITY_KIND" in
    snapshot)
      [ "$(qa_runtime_git -C "$CONTROL_PLANE_ROOT" rev-parse HEAD^{commit})" = "$CONTROL_PLANE_BASE_COMMIT" ] \
        && [ "$(qa_runtime_git -C "$CONTROL_PLANE_ROOT" rev-parse HEAD^{tree})" = "$CONTROL_PLANE_BASE_TREE" ] \
        || return 1
      current_control_plane_snapshot_digest="$(
        qa_firebase_endpoint_safe_env \
          /usr/bin/python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
          --repo "$CONTROL_PLANE_ROOT" \
          --repository "$CONTROL_PLANE_REPOSITORY" \
          --schema control-plane-snapshot/v1
      )" || return 1
      [ "$current_control_plane_snapshot_digest" = "$CONTROL_PLANE_SNAPSHOT_DIGEST" ]
      ;;
    clean)
      [ -z "$(qa_runtime_git -C "$CONTROL_PLANE_ROOT" status --porcelain --ignore-submodules=all)" ] \
        && [ "$(qa_runtime_git -C "$CONTROL_PLANE_ROOT" rev-parse HEAD^{commit})" = "$CONTROL_PLANE_COMMIT" ] \
        && [ "$(qa_runtime_git -C "$CONTROL_PLANE_ROOT" rev-parse HEAD^{tree})" = "$CONTROL_PLANE_TREE" ]
      ;;
    *) return 1 ;;
  esac
}

require_quality_identity_current() {
  local current_quality_snapshot_digest=""

  require_control_plane_identity_current || return 1
  [ -d "$QUALITY_ROOT" ] \
    && [ ! -L "$QUALITY_ROOT" ] \
    && [ "$(cd "$QUALITY_ROOT" && pwd -P)" = "$QUALITY_ROOT" ] \
    && [ "$(qa_runtime_git -C "$QUALITY_ROOT" remote get-url origin)" = "$QUALITY_REPOSITORY" ] \
    || return 1
  case "$QUALITY_IDENTITY_KIND" in
    snapshot)
      [ "$(qa_runtime_git -C "$QUALITY_ROOT" rev-parse HEAD^{commit})" = "$QUALITY_BASE_COMMIT" ] \
        && [ "$(qa_runtime_git -C "$QUALITY_ROOT" rev-parse HEAD^{tree})" = "$QUALITY_BASE_TREE" ] \
        || return 1
      current_quality_snapshot_digest="$(
        qa_firebase_endpoint_safe_env \
          /usr/bin/python3 -I "$SESSION_TRUSTED_SNAPSHOT_VERIFIER" \
          --repo "$QUALITY_ROOT" \
          --repository "$QUALITY_REPOSITORY" \
          --schema quality-snapshot/v1
      )" || return 1
      [ "$current_quality_snapshot_digest" = "$QUALITY_SNAPSHOT_DIGEST" ]
      ;;
    clean)
      [ -z "$(qa_runtime_git -C "$QUALITY_ROOT" status --porcelain --ignore-submodules=all)" ] \
        && [ "$(qa_runtime_git -C "$QUALITY_ROOT" rev-parse HEAD^{commit})" = "$QUALITY_COMMIT" ] \
        && [ "$(qa_runtime_git -C "$QUALITY_ROOT" rev-parse HEAD^{tree})" = "$QUALITY_TREE" ]
      ;;
    *) return 1 ;;
  esac
}

