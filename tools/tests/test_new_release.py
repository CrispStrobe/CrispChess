import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'asc'))
import new_release


class NewReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.notes = Path(self.tmp.name) / 'notes'
        self.notes.write_text('Startup fix')
        self.snapshot = {'versions': [{'version': '2.3.1', 'state': 'READY_FOR_SALE', 'build': '17'}],
                         'builds': [{'version': '2.3.2', 'build': '19', 'state': 'VALID'}]}
        self.patches = [patch.object(new_release, 'read_version', return_value=('2.3.2', '19')),
                        patch.object(new_release.status, 'release_status', return_value=self.snapshot),
                        patch.object(new_release.client, 'paged', side_effect=lambda path: (
                            [{'id': 'en', 'attributes': {'locale': 'en-US', 'whatsNew': 'Bug fixes'}}]
                            if 'appStoreVersionLocalizations?' in path else [])),
                        patch.object(new_release.client, 'expect', return_value={'data': {'id': 'target'}}),
                        patch.object(new_release, 'invoke')]
        self.mocks = [p.start() for p in self.patches]
        # Block any accidental real ASC request, including through helper functions.
        patch.object(new_release.client, 'call', side_effect=AssertionError('Live ASC access')).start()
        self.addCleanup(patch.stopall)

    def run_release(self):
        with contextlib.redirect_stdout(io.StringIO()):
            new_release.release('19', '17', self.notes, attempts=1)

    def test_creates_and_submits_after_guards(self):
        self.run_release()
        self.assertEqual(self.mocks[3].call_args.args[:2], ('POST', '/v1/appStoreVersions'))
        self.assertEqual(self.mocks[4].call_count, 4)

    def test_processing_does_not_mutate(self):
        self.snapshot['builds'][0]['state'] = 'PROCESSING'
        with self.assertRaises(ValueError): self.run_release()
        self.mocks[3].assert_not_called()

    def test_approved_release_changed(self):
        self.snapshot['versions'][0]['build'] = '18'
        with self.assertRaises(ValueError): self.run_release()
        self.mocks[3].assert_not_called()

    def test_other_submission_is_preserved(self):
        self.mocks[2].side_effect = None
        self.mocks[2].return_value = [{'id': 'other', 'attributes': {'state': 'IN_REVIEW'}}]
        with self.assertRaises(ValueError): self.run_release()
        self.mocks[3].assert_not_called()

    def add_target(self):
        self.snapshot['versions'].append({'id': 'target', 'version': '2.3.2',
                                          'state': 'PREPARE_FOR_SUBMISSION', 'build': '19'})

    def submission_reads(self, *, items, state='READY_FOR_REVIEW', notes='Bug fixes'):
        def pages(path):
            if 'reviewSubmissions?' in path:
                return [{'id': 'existing', 'attributes': {'state': state}}]
            if '/existing/items?include=appStoreVersion' in path:
                return items
            if '/target/appStoreVersionLocalizations?' in path:
                return [{'id': 'en', 'attributes': {'locale': 'en-US', 'whatsNew': notes}}]
            self.fail(f'Unexpected read: {path}')
        self.mocks[2].side_effect = pages

    def test_empty_ready_submission_allows_existing_target_recovery(self):
        self.add_target()
        self.submission_reads(items=[])
        self.run_release()
        self.mocks[3].assert_not_called()  # No duplicate version creation.
        self.assertEqual(self.mocks[4].call_count, 4)
        self.assertEqual(self.mocks[4].call_args_list[-2].args[1],
                         ['--build', '19', '--platform', 'MAC_OS', '--dry-run'])

    def test_empty_ready_submission_allows_new_target(self):
        self.submission_reads(items=[])
        self.run_release()
        self.assertEqual(self.mocks[3].call_args.args[:2], ('POST', '/v1/appStoreVersions'))
        self.assertEqual(self.mocks[4].call_count, 4)

    def test_unrelated_items_block_before_preparation(self):
        self.add_target()
        self.submission_reads(items=[{'relationships': {'appStoreVersion': {
            'data': {'type': 'appStoreVersions', 'id': 'other'}}}}])
        with self.assertRaisesRegex(ValueError, 'unrelated'):
            self.run_release()
        self.mocks[3].assert_not_called()
        self.mocks[4].assert_not_called()

    def test_existing_target_missing_notes_blocks_before_preparation(self):
        self.add_target()
        self.submission_reads(items=[], notes='  ')
        with self.assertRaisesRegex(ValueError, 'whatsNew.*en-US'):
            self.run_release()
        self.mocks[3].assert_not_called()
        self.mocks[4].assert_not_called()

    def test_newly_created_update_requires_notes_before_preparation(self):
        self.submission_reads(items=[], notes=None)
        with self.assertRaisesRegex(ValueError, 'whatsNew.*en-US'):
            self.run_release()
        # The version must exist to inspect its localizations; nothing else is written.
        self.assertEqual(self.mocks[3].call_count, 1)
        self.assertEqual(self.mocks[3].call_args.args[:2], ('POST', '/v1/appStoreVersions'))
        self.mocks[4].assert_not_called()

    def test_owned_rejected_submission_allows_resubmission(self):
        self.add_target()
        self.snapshot['versions'][-1]['state'] = 'REJECTED'
        self.submission_reads(state='UNRESOLVED_ISSUES', items=[{
            'relationships': {'appStoreVersion': {
                'data': {'type': 'appStoreVersions', 'id': 'target'}}}}])
        self.run_release()
        self.mocks[3].assert_not_called()
        self.assertEqual(self.mocks[4].call_count, 4)

    def test_empty_unresolved_submission_blocks_before_preparation(self):
        self.submission_reads(items=[], state='UNRESOLVED_ISSUES')
        with self.assertRaisesRegex(ValueError, 'not READY_FOR_REVIEW'):
            self.run_release()
        self.mocks[3].assert_not_called()
        self.mocks[4].assert_not_called()

    def test_multiple_open_submissions_block_before_preparation(self):
        self.mocks[2].side_effect = None
        self.mocks[2].return_value = [
            {'id': value, 'attributes': {'state': 'READY_FOR_REVIEW'}}
            for value in ('first', 'second')]
        with self.assertRaisesRegex(ValueError, 'Ambiguous active'):
            self.run_release()
        self.mocks[3].assert_not_called()
        self.mocks[4].assert_not_called()

    def test_target_already_pending_is_idempotent(self):
        self.snapshot['versions'].append({'version': '2.3.2', 'state': 'WAITING_FOR_REVIEW', 'build': '19'})
        self.run_release()
        self.mocks[3].assert_not_called()
        self.mocks[4].assert_not_called()

    def test_wrong_version_build_does_not_mutate(self):
        self.snapshot['builds'][0]['version'] = '2.3.3'
        with self.assertRaises(ValueError): self.run_release()
        self.mocks[3].assert_not_called()


if __name__ == '__main__': unittest.main()
