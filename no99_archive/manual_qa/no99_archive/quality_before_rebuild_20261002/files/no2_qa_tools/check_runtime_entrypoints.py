#!/usr/bin/env python3
"""以隔離 fixture 驗證已選定 Control、Quality 與原生 QA 入口。"""
import argparse
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--control', required=True, type=Path)
    parser.add_argument('--impl', required=True, type=Path)
    args = parser.parse_args()
    control, impl = args.control.resolve(), args.impl.resolve()
    quality = Path(__file__).resolve().parents[1]
    adapter = quality / 'no3_run_scripts/control_adapter'
    required = [
        adapter / 'programs/qa-runtime-phase.py',
        adapter / 'programs/qa-session-runtime.sh',
        adapter / 'tests/qa-runtime-phase-test.py',
        control / 'scripts/tests/qa-session-runtime-test.py',
        impl / 'src/qa/nativeProofHarness/run.sh',
        impl / 'src/qa/nativeProofHarness/proof_lifecycle_test.m',
        adapter / 'programs/qa-runtime-selection.py',
        adapter / 'tests/qa-runtime-selection-test.py',
        control / 'scripts/qa-runtime-input.py',
        control / 'scripts/tests/qa-binding-retention-test.py',
        adapter / 'programs/qa-first-launch.py',
        adapter / 'tests/qa-first-launch-test.py',
        impl / 'src/qa/nativeProofHarness/run_auth_network.sh',
    ]
    if any(not path.is_file() or path.is_symlink() for path in required):
        print('QA_RUNTIME_ENTRYPOINT_MISSING')
        return 1
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C',
                   'QA_QUALITY_TEST_ROOT': str(quality), 'QA_CONTROL_TEST_ROOT': str(control),
                   'PYTHONDONTWRITEBYTECODE': '1', 'TMPDIR': os.environ.get('TMPDIR', '/tmp')}
    try:
        rendered = subprocess.check_output(
            ['/usr/bin/python3', '-B', str(control / 'scripts/render_qa_contract.py'),
             '--quality-root', str(quality)], env=environment, stderr=subprocess.DEVNULL, text=True)
    except (OSError, subprocess.CalledProcessError):
        print('QA_RUNTIME_SOURCE_REJECTED')
        return 1
    if any(value not in rendered for value in (
            'source "$SESSION_QUALITY_ROOT/no3_run_scripts/control_adapter/programs/qa-session-runtime.sh"',
            'run_and_validate_qa_bootstrap || exit 1', 'qa_session_command_loop',
            '--quality-root "$SESSION_QUALITY_ROOT" --snapshot')):
        print('QA_RUNTIME_ENTRYPOINT_NOT_WIRED')
        return 1
    commands = [
        ['/usr/bin/python3', '-I', str(required[2])],
        ['/usr/bin/python3', '-I', str(required[3])],
        ['/usr/bin/python3', '-I', str(required[7])],
        ['/usr/bin/python3', '-I', str(required[9])],
        ['/usr/bin/python3', '-I', str(required[11])],
        ['/bin/bash', '--noprofile', '--norc', str(required[12])],
        ['/bin/bash', '--noprofile', '--norc', str(required[4])],
    ]
    for command in commands:
        try:
            result = subprocess.run(command, env=environment, capture_output=True,
                                    timeout=60, cwd=impl if command == commands[-1] else control)
        except (OSError, subprocess.TimeoutExpired):
            print('QA_RUNTIME_BEHAVIOR_FAILED')
            return 1
        if result.returncode != 0:
            print('QA_RUNTIME_BEHAVIOR_FAILED:' + Path(command[-1]).name)
            return 1
    print('QA_RUNTIME_BEHAVIOR_PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
