#!/usr/bin/env python3
"""Resolve a registered Quality owner and verify its finite adapter bundle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROFILE = 'susugigi-accounting-ios-v1'
OWNER = 'SuSuGiGi/no2_accounting_app'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def regular_path(root, relative):
    relative = Path(relative)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('invalid_path')
    path = root / relative
    for parent in [path, *path.parents]:
        if parent.is_symlink():
            raise ValueError('redirected_source')
        if parent == root:
            break
    if not path.is_file():
        raise ValueError('source_missing:' + str(relative))
    return path


def git_value(root, *args):
    environment = {'PATH': os.defpath, 'LC_ALL': 'C',
                   'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull}
    return subprocess.check_output(
        ['git', '-C', str(root), '-c', 'core.fsmonitor=false', *args],
        env=environment, stderr=subprocess.DEVNULL, text=True).strip()


def check(root, profile, quality_root, snapshot=False):
    locator = json.loads(regular_path(root, 'manifests/qa_adapters.json').read_text())
    if locator['schema_version'] != 1 or profile not in locator['profiles']:
        raise ValueError('unsupported_profile')
    binding = locator['profiles'][profile]
    quality_root = Path(quality_root).absolute()
    if quality_root != quality_root.resolve():
        raise ValueError('redirected_quality_root')
    if not snapshot:
        if Path(git_value(quality_root, 'rev-parse', '--show-toplevel')) != quality_root:
            raise ValueError('quality_git_root_mismatch')
        if git_value(quality_root, 'remote', 'get-url', 'origin') != binding['repository']:
            raise ValueError('quality_repository_mismatch')
    elif quality_root.stat().st_mode & 0o222:
        raise ValueError('mutable_snapshot')
    manifest_path = regular_path(quality_root, binding['manifest'])
    if digest(manifest_path) != binding['manifest_sha256']:
        raise ValueError('manifest_changed')
    manifest = json.loads(manifest_path.read_text())
    if (manifest['schema_version'] != 2 or manifest['profile'] != profile
            or manifest['owner'] != binding['owner']
            or manifest['repository'] != binding['repository']
            or manifest['adapter_root'] != binding['adapter_root']):
        raise ValueError('identity_mismatch')
    rows = manifest['sections'] + manifest['programs']
    seen = set()
    for row in rows:
        relative = row['program']
        if relative in seen or not relative.startswith(binding['adapter_root'] + '/'):
            raise ValueError('wrong_owner_path')
        seen.add(relative)
        path = regular_path(quality_root, relative)
        if snapshot and path.stat().st_mode & 0o222:
            raise ValueError('mutable_snapshot')
        if digest(path) != row['sha256']:
            raise ValueError('source_changed:' + relative)
    return {'schema_version': 2, 'profile': profile, 'owner': binding['owner'],
            'repository': binding['repository'], 'adapter_root': binding['adapter_root'],
            'checked_files': len(rows), 'result': 'bundle_integrity_valid',
            'identity_mode': 'previously_locked_private_snapshot' if snapshot else 'selected_quality_git',
            'runtime_result': 'not_executed'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['check'])
    parser.add_argument('--profile', required=True)
    parser.add_argument('--quality-root', required=True, type=Path)
    parser.add_argument('--snapshot', action='store_true',
                        help='Only for the already identity-verified immutable session copy')
    args = parser.parse_args()
    try:
        print(json.dumps(check(ROOT, args.profile, args.quality_root, args.snapshot), ensure_ascii=False))
        return 0
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(json.dumps({'result': 'rejected', 'reason': str(error)}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
