#!/usr/bin/env python3
"""Exercise failure recovery with synthetic identities and no external access."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

QUALITY = Path(os.environ['QA_QUALITY_TEST_ROOT'])
RUNTIME = QUALITY / 'no3_run_scripts/control_adapter'


def function(path, name):
    text = path.read_text()
    match = re.search(r'^' + name + r'\(\) \{\n.*?^\}', text, re.M | re.S)
    assert match is not None, name
    return match.group()


class BindingTests(unittest.TestCase):
    def test_failed_query_keeps_cleanup_owner(self):
        binder = function(RUNTIME / 'ios_runtime/firestore_binding_1.sh',
                          'bind_qa_session_uid_from_sqlite')
        cleanup = function(RUNTIME / 'ios_runtime/session_cleanup_1.sh',
                           'run_bound_qa_fixture_cleanup')
        for mode in ('missing', 'failed', 'zero', 'duplicate', 'success', 'conflict'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                helper = root / 'no2_qa_tools/cleanup_qa_fixtures.sh'
                helper.parent.mkdir()
                helper.write_text('# synthetic helper\n')
                script = binder + '\n' + cleanup + r'''
set -eu
QA_FIREBASE_PROJECT_ID=susugigi-qa
QA_SESSION_UID=synthetic-owner
if [ "$MODE" = conflict ]; then QA_SESSION_UID=other-owner; fi
READY_IDENTITY_HASH="$TEST_HASH"
require_session_runtime_snapshots_current() { return 0; }
if [ "$MODE" != missing ]; then
  run_qa_sqlite_local_probe() {
    [ "$MODE" != failed ] || return 1
    printf '%s\n' id ----------------
    case "$MODE" in
      success|conflict) printf '%s\n' synthetic-owner ;;
      duplicate) printf '%s\n' synthetic-owner synthetic-owner ;;
      zero) printf '%s\n' unknown-owner ;;
    esac
  }
fi
if bind_qa_session_uid_from_sqlite; then status=0; else status=$?; fi
if [ "$MODE" = success ]; then test "$status" = 0; else test "$status" != 0; fi
if [ "$MODE" = conflict ]; then
  test "$QA_SESSION_UID" = other-owner
  exit 0
fi
test "$QA_SESSION_UID" = synthetic-owner
run_session_snapshot_command() {
  local uid
  IFS= read -r uid
  test "$uid" = synthetic-owner
  printf cleaned > "$SESSION_QUALITY_ROOT/receipt"
}
run_bound_qa_fixture_cleanup
test -f "$SESSION_QUALITY_ROOT/receipt"
'''
                result = subprocess.run(['/bin/bash', '--noprofile', '--norc'],
                    input=script, capture_output=True, text=True, timeout=5,
                    env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'MODE': mode,
                         'SESSION_QUALITY_ROOT': temporary,
                         'TEST_HASH': hashlib.sha256(b'synthetic-owner').hexdigest()})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout + result.stderr, '')

    def test_missing_dependencies_prevent_app_mount(self):
        body = function(RUNTIME / 'programs/qa-session-runtime.sh',
                        'run_and_validate_qa_open_app_operation')
        for missing in ('run_qa_sqlite_local_probe', 'require_r03_initial_backup_markers'):
            other = ('require_r03_initial_backup_markers' if missing == 'run_qa_sqlite_local_probe'
                     else 'run_qa_sqlite_local_probe')
            script = body + f'\n{other}() {{ :; }}\n' + r'''
IDENTITY_TEARDOWN_CONFIRMED=1
require_session_runtime_snapshots_current() { printf unexpected-mount; return 1; }
run_and_validate_qa_open_app_operation
'''
            result = subprocess.run(['/bin/bash', '--noprofile', '--norc'],
                input=script, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, 'QA_OPERATION_DEPENDENCY_MISSING\n')

    def test_metro_does_not_consume_runner_commands(self):
        source = (RUNTIME / 'ios_runtime/metro_1.sh').read_text()
        command = source[source.rindex('npx react-native start'):]
        with tempfile.TemporaryDirectory() as temporary:
            script = r'''
set -m
npx() {
  /usr/bin/python3 -c 'import os,sys; sys.exit(0 if os.fstat(0).st_rdev == os.stat("/dev/null").st_rdev else 9)'
}
''' + command + '\nwait "$METRO_PID"\n'
            result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', script],
                input='status\n', capture_output=True, text=True, timeout=5,
                env={'PATH': '/usr/bin:/bin', 'METRO_STREAM_FIFO': str(Path(temporary) / 'output')})
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
