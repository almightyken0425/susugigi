#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('first_launch', ROOT / 'programs/qa-first-launch.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
p = m.phase
TOKEN = 'a' * 64
UID = 'disposable-test-user'
HASH = p.digest(UID)
REQUEST = 'first-launch-' + 'b' * 32


def proof():
    return dict(tokenHash=p.digest(TOKEN), uidHash=HASH, expiresAt=time.time() + 100,
                state='active', consumedBindings=[], consumedRequestHashes=[])


def window():
    return ['QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY',
            'QA BOOT anonymous signIn start', 'QA NATIVE AUTH_NETWORK_BLOCKED',
            'QA BOOT anonymous signIn start', 'QA NATIVE AUTH_NETWORK_BLOCKED',
            'QA NATIVE AUTH_NETWORK_RESTORED', 'QA BOOT anonymous signIn start',
            'QA READY ' + json.dumps(dict(schema='qa.runtime/v1', requestId=REQUEST,
                state='ready', isAnonymous=True, identityMode='disposable-anonymous', identityHash=HASH))]


def rows():
    result = {table: [] for table in m.TABLES}
    result['users'] = [dict(id=UID, email=None)]
    result['settings'] = [dict(id='settings', user_id=UID, language='zh-Hant', launch_mode='home')]
    result['accounts'] = [dict(id=str(i), user_id=UID, name=name, icon_id=icon, sort_order=i, currency_code='TWD')
                          for i, (name, icon) in enumerate([('現金', 1), ('信用卡', 7)])]
    result['categories'] = [dict(id=str(i), user_id=UID, name=name, type=kind, icon_id=icon, sort_order=sort)
                           for i, (name, kind, icon, sort) in enumerate([
                               ('餐飲', 'expense', 12, 0), ('交通', 'expense', 22, 1), ('購物', 'expense', 28, 2),
                               ('薪資', 'income', 88, 0), ('獎金', 'income', 91, 1)])]
    return result


class FirstLaunchTests(unittest.TestCase):
    def test_failed_first_launch_reports_only_allowlisted_stage_code(self):
        lines = ['QA RESULT ' + json.dumps(dict(schema='qa.runtime/v1', requestId=REQUEST,
                 operation='launch', value=None, error='QA_FIRST_LAUNCH_NATIVE_PREPARE_FAILED'))]
        kwargs = dict(phase='first-launch', request_id=REQUEST, token=TOKEN,
                      expected_identity=None, proof=None, now=time.time(), elapsed=1)
        with self.assertRaisesRegex(p.ReportedFailure, '^QA_FIRST_LAUNCH_NATIVE_PREPARE_FAILED$'):
            p.validate_ready_window(lines, **kwargs)
        with self.assertRaises(p.Invalid):
            p.validate_ready_window([lines[0].replace('QA_FIRST_LAUNCH_NATIVE_PREPARE_FAILED', 'secret')], **kwargs)

    def test_pre_ready_filter_only_allows_bound_first_launch_attempt(self):
        command = ['/usr/bin/python3', '-I', str(ROOT / 'programs/qa-safe-marker-filter.py'),
                   '--allow-golden-marker', 'QA BOOT']
        markers = 'QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY\nQA BOOT anonymous signIn start\n'
        rejected = 'QA RUNTIME MARKER REJECTED'
        self.assertIn(rejected, subprocess.check_output(command, input=markers, text=True))
        self.assertEqual(subprocess.check_output(command + ['--allow-first-launch', 'true'],
                         input=markers, text=True), markers)
        for value in ['QA BOOT anonymous signIn start\n', markers + 'QA BOOT delegate task=runBackup trigger=bootstrap\n',
                      markers + 'QA BOOT anonymous signIn start uid=secret\n']:
            self.assertIn(rejected, subprocess.check_output(command + ['--allow-first-launch', 'true'],
                          input=value, text=True))

    def test_ready_requires_real_offline_attempts_and_restoration(self):
        kwargs = dict(phase='first-launch', request_id=REQUEST, token=TOKEN,
                      expected_identity=None, proof=proof(), now=time.time(), elapsed=120)
        self.assertEqual(p.validate_ready_window(window(), **kwargs), HASH)
        for marker in ['QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY', 'QA NATIVE AUTH_NETWORK_BLOCKED',
                       'QA NATIVE AUTH_NETWORK_RESTORED', 'QA BOOT anonymous signIn start']:
            changed = window()
            changed.remove(marker)
            with self.assertRaises(p.Invalid):
                p.validate_ready_window(changed, **kwargs)
        with self.assertRaises(p.Invalid):
            p.validate_ready_window(window(), **{**kwargs, 'elapsed': 601})

    def test_home_requires_consumed_first_launch_binding_and_one_home(self):
        data = proof()
        data['consumedBindings'] = [p.digest('first-launch:true')]
        data['consumedRequestHashes'] = [p.digest(REQUEST)]
        kwargs = dict(phase='first-home', request_id=REQUEST, token=TOKEN,
                      expected_identity=HASH, proof=data, now=time.time(), elapsed=1)
        home = 'QA BOOT resolve premiumLoaded=true landing=sha256:' + p.digest('home')
        with self.assertRaises(p.Pending):
            p.validate_ready_window(window(), **kwargs)
        self.assertEqual(p.validate_ready_window(window() + [home], **kwargs), HASH)
        with self.assertRaises(p.Invalid):
            p.validate_ready_window(window() + [home, home], **kwargs)
        with self.assertRaises(p.Invalid):
            p.validate_ready_window(window() + [home], **{**kwargs, 'proof': proof()})

    def test_release_is_exact_token_bound_atomic_and_not_overwritable(self):
        with tempfile.TemporaryDirectory() as temp:
            container = Path(temp) / 'data/Containers/Data/Application/fixture'
            directory = container / 'Library/Application Support/qa_runtime'
            directory.mkdir(parents=True)
            container = container.resolve()
            directory = directory.resolve()
            (container / '.com.apple.mobile_container_manager.metadata.plist').write_bytes(
                plistlib.dumps({'MCMMetadataIdentifier': p.QA_BUNDLE}))
            (directory / 'qa_session_proof_v1.plist').write_bytes(plistlib.dumps(proof()))
            secret = dict(token=TOKEN, expectedIdentity=HASH)
            with self.assertRaises(p.Invalid):
                m.release(str(container), REQUEST, {**secret, 'token': 'd' * 64})
            self.assertFalse((directory / 'qa_first_launch_release_v1.plist').exists())
            m.release(str(container), REQUEST, secret)
            receipt = plistlib.loads((directory / 'qa_first_launch_release_v1.plist').read_bytes())
            self.assertEqual(receipt, dict(tokenHash=p.digest(TOKEN), uidHash=HASH, requestHash=p.digest(REQUEST)))
            with self.assertRaises(FileExistsError):
                m.release(str(container), REQUEST, secret)
            self.assertFalse((directory / 'qa_first_launch_release_v1.pending').exists())
            (container / '.com.apple.mobile_container_manager.metadata.plist').write_bytes(
                plistlib.dumps({'MCMMetadataIdentifier': 'production'}))
            with self.assertRaises(ValueError):
                m.release(str(container), REQUEST, secret)

    def test_default_evidence_rejects_duplicates_wrong_owners_and_tombstones(self):
        original = rows()
        baseline = m.defaults_signature(original, HASH)
        reverse = copy.deepcopy(original)
        reverse['categories'].reverse()
        self.assertEqual(m.defaults_signature(reverse, HASH), baseline)
        for change in [
                lambda r: r['accounts'].append(copy.deepcopy(r['accounts'][0])),
                lambda r: r['categories'][0].update(user_id='other'),
                lambda r: r['accounts'][0].update(deleted_on=123),
                lambda r: r['accounts'][0].update(_status='deleted'),
                lambda r: r['categories'][0].update(name='incorrect'),
                lambda r: r['users'][0].update(id='other'),
                lambda r: r['transactions'].append(dict(id='unexpected'))]:
            changed = copy.deepcopy(original)
            change(changed)
            with self.assertRaises(ValueError):
                m.defaults_signature(changed, HASH)
        changed = copy.deepcopy(original)
        changed['accounts'][0]['id'] = 'rebuilt-id'
        self.assertNotEqual(m.defaults_signature(changed, HASH), baseline)


if __name__ == '__main__':
    unittest.main()
