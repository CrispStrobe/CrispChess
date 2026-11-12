from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'asc'))
import replace_build as replacement

class ReplacementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.notes = Path(self.temp.name) / 'notes.txt'
        self.notes.write_text('CrispChess name and launch verified in build 18.')
        self.version = {'id': 'mac-version', 'attributes': {'platform': 'MAC_OS',
            'versionString': '2.3.1', 'appStoreState': 'WAITING_FOR_REVIEW'}}
        self.attached = '17'
        self.build = {'id': 'new-build', 'attributes': {'version': '18', 'processingState': 'VALID'}}
        self.release = {'platform': 'MAC_OS', 'version': '2.3.1'}
        self.items = [{'relationships': {'appStoreVersion': {'data': {'id': 'mac-version'}}}}]
        patch.object(replacement, 'read_version', return_value=('2.3.1', '18')).start()
        self.paged = patch.object(replacement.client, 'paged', side_effect=self.pages).start()
        self.expect = patch.object(replacement.client, 'expect', side_effect=self.request).start()
        self.invoke = patch.object(replacement, 'invoke').start()
        self.addCleanup(patch.stopall)

    def pages(self, path):
        if '/items?' in path: return self.items
        if 'reviewSubmissions?' in path:
            return [{'id': 'pending', 'attributes': {'state': 'WAITING_FOR_REVIEW'}}]
        if 'appStoreVersions?' in path: return [self.version]
        return [self.build]

    def request(self, method, path, body=None):
        if method == 'PATCH': return {}
        if '/reviewSubmissions/' in path: return {'data': {'attributes': {'state': 'COMPLETE'}}}
        if 'preReleaseVersion' in path: return {'data': {'attributes': self.release}}
        if path.endswith('/build'): return {'data': {'attributes': {'version': self.attached}}}
        return {'data': {'attributes': {'appStoreState': 'DEVELOPER_REJECTED', 'versionString': '2.3.1'}}}

    def run_replacement(self):
        with redirect_stdout(io.StringIO()):
            replacement.replace('18', '17', self.notes, attempts=1, interval=0)

    def assert_no_mutation(self):
        self.assertFalse(any(call.args[0] != 'GET' for call in self.expect.call_args_list))
        self.invoke.assert_not_called()

    def test_replaces_only_its_own_pending_submission_after_processing(self):
        self.run_replacement()
        writes = [call for call in self.expect.call_args_list if call.args[0] == 'PATCH']
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0].args[1], '/v1/reviewSubmissions/pending')
        self.assertEqual(writes[0].args[2]['data']['attributes'], {'canceled': True})
        self.assertEqual(self.invoke.call_count, 4)
        self.assertEqual(self.invoke.call_args_list[0].args[1], ['--build','18','--platform','MAC_OS','--attach-only'])

    def test_invalid_or_unprocessed_replacement_preserves_current_submission(self):
        for state in ('PROCESSING','FAILED','INVALID'):
            with self.subTest(state=state):
                self.build['attributes']['processingState'] = state
                self.expect.reset_mock()
                with self.assertRaises(ValueError): self.run_replacement()
                self.assert_no_mutation()

    def test_ios_build_with_same_number_cannot_replace_mac(self):
        self.release['platform'] = 'IOS'
        with self.assertRaises(ValueError): self.run_replacement()
        self.assert_no_mutation()

    def test_wrong_marketing_version_is_rejected(self):
        self.release['version'] = '2.3.2'
        with self.assertRaises(ValueError): self.run_replacement()
        self.assert_no_mutation()

    def test_changed_current_build_is_preserved(self):
        self.attached = '19'
        with self.assertRaisesRegex(ValueError, 'changed'): self.run_replacement()
        self.assert_no_mutation()

    def test_approved_version_is_not_withdrawn(self):
        self.version['attributes']['appStoreState'] = 'READY_FOR_DISTRIBUTION'
        with self.assertRaisesRegex(ValueError, 'READY_FOR_DISTRIBUTION'): self.run_replacement()
        self.assert_no_mutation()

    def test_submission_with_other_items_is_preserved(self):
        self.items.append({'relationships': {}})
        with self.assertRaisesRegex(ValueError, 'other items'): self.run_replacement()
        self.assert_no_mutation()

    def test_already_submitted_replacement_is_a_noop(self):
        self.attached = '18'
        self.run_replacement()
        self.assert_no_mutation()

    def test_changed_build_after_withdrawal_is_not_overwritten(self):
        original = self.request
        def request(method, path, body=None):
            if method == 'PATCH': self.attached = '19'
            return original(method, path, body)
        self.expect.side_effect = request
        with self.assertRaisesRegex(ValueError, 'changed during preparation'):
            self.run_replacement()
        self.invoke.assert_not_called()
