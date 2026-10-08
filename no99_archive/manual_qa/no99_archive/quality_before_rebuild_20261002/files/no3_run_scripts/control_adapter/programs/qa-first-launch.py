#!/usr/bin/env python3
"""R14 cleanup acknowledgement and independent, bounded QA SQLite evidence."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import sqlite3
import tempfile
import time

_spec = importlib.util.spec_from_file_location('runtime_phase', Path(__file__).with_name('qa-runtime-phase.py'))
phase = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(phase)
TABLES = ('users', 'settings', 'accounts', 'categories', 'transactions', 'transfers', 'schedules', 'currency_rates', 'currency_configs')


@contextmanager
def container_directory(container, components=()):
    root = Path(container)
    if (not root.is_absolute() or root.resolve() != root
            or root.parts[-5:-1] != ('data', 'Containers', 'Data', 'Application')):
        raise ValueError()
    fds = []
    try:
        fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
        fds.append(fd)
        for part in root.parts[1:]:
            fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            fds.append(fd)
        metadata = plistlib.loads(phase.read_regular_at(fd, '.com.apple.mobile_container_manager.metadata.plist'))
        if metadata.get('MCMMetadataIdentifier') != phase.QA_BUNDLE:
            raise ValueError()
        for part in components:
            fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            fds.append(fd)
        yield fd
    finally:
        for fd in reversed(fds):
            os.close(fd)


def release(container, request, secret):
    if not re.fullmatch(r'first-launch-[0-9a-f]{32}', request or ''):
        raise ValueError()
    with container_directory(container, ('Library', 'Application Support', 'qa_runtime')) as directory:
        proof = plistlib.loads(phase.read_regular_at(directory, 'qa_session_proof_v1.plist'))
        phase.validate_proof(proof, token=secret['token'], identity=secret['expectedIdentity'], now=time.time())
        if proof['consumedBindings'] or proof['consumedRequestHashes']:
            raise ValueError()
        receipt = plistlib.dumps(dict(tokenHash=phase.digest(secret['token']),
                                      uidHash=secret['expectedIdentity'], requestHash=phase.digest(request)))
        pending = 'qa_first_launch_release_v1.pending'
        fd = os.open(pending,
                     os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(receipt)
                stream.flush()
                os.fsync(stream.fileno())
            os.link(pending, 'qa_first_launch_release_v1.plist',
                    src_dir_fd=directory, dst_dir_fd=directory, follow_symlinks=False)
        finally:
            os.unlink(pending, dir_fd=directory)


def defaults_signature(rows, expected_identity):
    counts = {table: len(rows[table]) for table in TABLES}
    if any(counts[table] != count for table, count in dict(
            users=1, settings=1, accounts=2, categories=5, transactions=0,
            transfers=0, schedules=0, currency_rates=0).items()):
        raise ValueError()
    user = rows['users'][0]
    uid = user['id']
    if phase.digest(uid) != expected_identity or user.get('email') not in ('', None):
        raise ValueError()
    for table in TABLES:
        for row in rows[table]:
            if (row.get('_status') == 'deleted' or row.get('deleted_on') is not None
                    or row.get('disabled_on') is not None
                    or (table != 'users' and row['user_id'] != uid)):
                raise ValueError()
    settings = rows['settings'][0]
    if settings['language'] != 'zh-Hant' or settings['launch_mode'] != 'home':
        raise ValueError()
    expected_accounts = [('現金', 1, 0), ('信用卡', 7, 1)]
    actual_accounts = sorted((row['name'], row['icon_id'], row['sort_order']) for row in rows['accounts'])
    if actual_accounts != sorted(expected_accounts) or any(row['currency_code'] != 'TWD' for row in rows['accounts']):
        raise ValueError()
    expected_categories = [('餐飲', 'expense', 12, 0), ('交通', 'expense', 22, 1),
                           ('購物', 'expense', 28, 2), ('薪資', 'income', 88, 0), ('獎金', 'income', 91, 1)]
    actual_categories = sorted((row['name'], row['type'], row['icon_id'], row['sort_order']) for row in rows['categories'])
    if actual_categories != sorted(expected_categories):
        raise ValueError()
    currency_ids = [row['currency_id'] for row in rows['currency_configs']]
    if len(currency_ids) != len(set(currency_ids)):
        raise ValueError()
    stable = {table: sorted(row['id'] for row in rows[table]) for table in TABLES}
    return hashlib.sha256(json.dumps(stable, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def inspect_database(container, expected_identity, empty=False):
    with container_directory(container, ('Documents',)) as directory, tempfile.TemporaryDirectory(prefix='qa-r14-sqlite-') as temp:
        for suffix in ('', '-wal', '-shm'):
            name = 'watermelon.db' + suffix
            try:
                data = phase.read_regular_at(directory, name, 64 * 1048576)
            except FileNotFoundError:
                if suffix:
                    continue
                raise
            (Path(temp) / name).write_bytes(data)
        connection = sqlite3.connect('file:' + str(Path(temp) / 'watermelon.db') + '?mode=ro', uri=True)
        try:
            connection.row_factory = sqlite3.Row
            rows = {table: [dict(row) for row in connection.execute('SELECT * FROM ' + table + ' LIMIT 1001')] for table in TABLES}
        finally:
            connection.close()
        if empty:
            if any(rows.values()):
                raise ValueError()
            return 'QA_R14_EMPTY_DATABASE_VERIFIED'
        return defaults_signature(rows, expected_identity)


def main():
    import sys
    parser = argparse.ArgumentParser()
    parser.add_argument('--action', choices=('release', 'defaults', 'empty', 'reset-check'), required=True)
    parser.add_argument('--data-container', required=True)
    parser.add_argument('--request-id')
    args = parser.parse_args()
    try:
        if args.action == 'reset-check':
            with container_directory(args.data_container):
                proof = Path(args.data_container) / 'Library/Application Support/qa_runtime/qa_session_proof_v1.plist'
                if proof.exists() or proof.is_symlink():
                    raise ValueError()
            print('QA_R14_FRESH_INSTALL_ALLOWED')
            return 0
        if args.action == 'empty':
            with container_directory(args.data_container, ('Library', 'Application Support', 'qa_runtime')) as directory:
                try:
                    os.stat('qa_session_proof_v1.plist', dir_fd=directory, follow_symlinks=False)
                except FileNotFoundError:
                    pass
                else:
                    raise ValueError()
            print(inspect_database(args.data_container, None, empty=True))
            return 0
        secret = json.loads(sys.stdin.buffer.read(4097))
        if set(secret) != {'token', 'expectedIdentity'} or not all(phase.valid_hash(value) for value in secret.values()):
            raise ValueError()
        if args.action == 'release':
            release(args.data_container, args.request_id, secret)
            print('QA_R14_CLEANUP_OWNERSHIP_ACKNOWLEDGED')
        else:
            proof = phase.read_qa_proof(args.data_container)
            phase.validate_proof(proof, token=secret['token'], identity=secret['expectedIdentity'], now=time.time())
            print(inspect_database(args.data_container, secret['expectedIdentity']))
        return 0
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error):
        print('QA_R14_EVIDENCE_REJECTED', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
