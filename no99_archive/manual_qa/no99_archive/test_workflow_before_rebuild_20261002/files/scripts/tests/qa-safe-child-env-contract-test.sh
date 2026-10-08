#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$SCRIPT_ROOT/scripts/qa-safe-child-env.py"
PYTHON_BIN="/usr/bin/python3"
TRUSTED_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
RAW_UID='syntheticQaUidForInjectionTest'
RAW_TOKEN='syntheticQaTokenForInjectionTest'

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

cat > "$TEST_ROOT/bash-env" <<'BASH_ENV_PAYLOAD'
printf '%s\n' "$RAW_UID" > "$QA_SENTINEL_PATH"
BASH_ENV_PAYLOAD
cat > "$TEST_ROOT/child" <<'CHILD'
#!/usr/bin/env bash
printf child-ran > "$QA_CHILD_PATH"
case ":$SHELLOPTS:" in
  *:xtrace:*) exit 71 ;;
esac
CHILD
chmod 700 "$TEST_ROOT/child"

: > "$TEST_ROOT/child-state"
if BASH_ENV="$TEST_ROOT/bash-env" \
  RAW_UID="$RAW_UID" \
  QA_SENTINEL_PATH="$TEST_ROOT/sentinel" \
  QA_CHILD_PATH="$TEST_ROOT/child-state" \
  PATH="$TRUSTED_PATH" \
  "$PYTHON_BIN" -I "$HELPER" -- bash "$TEST_ROOT/child" \
  > "$TEST_ROOT/rejected.out" 2> "$TEST_ROOT/rejected.err"; then
  echo 'BASH_ENV injection was accepted' >&2
  exit 1
fi
[ ! -e "$TEST_ROOT/sentinel" ]
[ ! -s "$TEST_ROOT/child-state" ]
[ ! -s "$TEST_ROOT/rejected.out" ]
grep -Fxq QA_RUNTIME_ENVIRONMENT_REJECTED "$TEST_ROOT/rejected.err"
! grep -Fq "$RAW_UID" "$TEST_ROOT/rejected.out" "$TEST_ROOT/rejected.err"

: > "$TEST_ROOT/child-state"
env \
  SHELLOPTS=xtrace \
  BASHOPTS=extdebug \
  QA_CHILD_PATH="$TEST_ROOT/child-state" \
  PATH="$TRUSTED_PATH" \
  "$PYTHON_BIN" -I "$HELPER" -- bash "$TEST_ROOT/child" \
  > "$TEST_ROOT/cleared.out" 2> "$TEST_ROOT/cleared.err"
grep -Fxq child-ran "$TEST_ROOT/child-state"
[ ! -s "$TEST_ROOT/cleared.out" ]
[ ! -s "$TEST_ROOT/cleared.err" ]

for function_name in shasum env python3 bash git plutil; do
  function_sentinel="$TEST_ROOT/function-$function_name"
  function_payload='() { printf function-ran > "$QA_FUNCTION_SENTINEL"; }'
  : > "$TEST_ROOT/function-$function_name.out"
  : > "$TEST_ROOT/function-$function_name.err"
  if /usr/bin/env \
      "BASH_FUNC_${function_name}%%=$function_payload" \
      PATH="$TRUSTED_PATH" \
      QA_FUNCTION_SENTINEL="$function_sentinel" \
      RAW_UID="$RAW_UID" \
      RAW_TOKEN="$RAW_TOKEN" \
      "$PYTHON_BIN" -I "$HELPER" -- /bin/bash -c "$function_name" \
      > "$TEST_ROOT/function-$function_name.out" \
      2> "$TEST_ROOT/function-$function_name.err"; then
    echo "BASH function injection was accepted: $function_name" >&2
    exit 1
  fi
  [ ! -e "$function_sentinel" ]
  [ ! -s "$TEST_ROOT/function-$function_name.out" ]
  grep -Fxq QA_RUNTIME_ENVIRONMENT_REJECTED \
    "$TEST_ROOT/function-$function_name.err"
  ! grep -Fq "$RAW_UID" \
    "$TEST_ROOT/function-$function_name.out" \
    "$TEST_ROOT/function-$function_name.err"
  ! grep -Fq "$RAW_TOKEN" \
    "$TEST_ROOT/function-$function_name.out" \
    "$TEST_ROOT/function-$function_name.err"
done

mkdir "$TEST_ROOT/attacker-bin"
cat > "$TEST_ROOT/attacker-bin/bash" <<'ATTACKER'
#!/bin/sh
printf attacker-ran > "$QA_PATH_SENTINEL"
ATTACKER
chmod 700 "$TEST_ROOT/attacker-bin/bash"
if PATH="$TEST_ROOT/attacker-bin:$TRUSTED_PATH" \
  QA_PATH_SENTINEL="$TEST_ROOT/path-sentinel" \
  RAW_UID="$RAW_UID" \
  RAW_TOKEN="$RAW_TOKEN" \
  "$PYTHON_BIN" -I "$HELPER" -- bash -c : \
  > "$TEST_ROOT/path.out" 2> "$TEST_ROOT/path.err"; then
  echo 'user-controlled PATH was accepted' >&2
  exit 1
fi
[ ! -e "$TEST_ROOT/path-sentinel" ]
[ ! -s "$TEST_ROOT/path.out" ]
grep -Fxq QA_RUNTIME_ENVIRONMENT_REJECTED "$TEST_ROOT/path.err"
! grep -Fq "$RAW_UID" "$TEST_ROOT/path.out" "$TEST_ROOT/path.err"
! grep -Fq "$RAW_TOKEN" "$TEST_ROOT/path.out" "$TEST_ROOT/path.err"

cat > "$TEST_ROOT/path-child" <<'PATH_CHILD'
#!/bin/sh
/usr/bin/python3 -I - <<'VERIFY_PATH'
import os
import pathlib
import stat
entries = os.environ['PATH'].split(':')
trusted = ['/usr/bin', '/bin', '/usr/sbin', '/sbin']
if entries != trusted:
    assert len(entries) == 5 and entries[1:] == trusted
    proxy = pathlib.Path(entries[0])
    info = proxy.lstat()
    assert proxy.name.startswith('susugigi-qa-tools.')
    assert stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700
    assert info.st_uid == os.getuid()
    files = list(proxy.iterdir())
    assert files and {p.name for p in files} <= {'firebase', 'gcloud', 'node'}
    for path in files:
        assert not path.is_symlink() and path.is_file()
        assert stat.S_IMODE(path.stat().st_mode) == 0o700
        assert path.read_text().startswith('#!/bin/sh\nexec ')
with open(os.environ['QA_PATH_OUTPUT'], 'w') as output:
    output.write('QA_TRUSTED_CHILD_PATH\n')
VERIFY_PATH
PATH_CHILD
chmod 700 "$TEST_ROOT/path-child"
PATH="$TRUSTED_PATH" \
  QA_PATH_OUTPUT="$TEST_ROOT/fixed-path" \
  "$PYTHON_BIN" -I "$HELPER" -- /bin/bash "$TEST_ROOT/path-child"
grep -Fxq QA_TRUSTED_CHILD_PATH "$TEST_ROOT/fixed-path"

echo 'qa-safe-child-env contract tests passed'
