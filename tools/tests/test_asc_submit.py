"""Exercise submission safety entirely through mocked ASC reads and writes."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'asc'))
import submit


class SubmitTests(unittest.TestCase):
    def setUp(self):
        self.version = {'id': 'target', 'attributes': {'platform': 'MAC_OS',
            'versionString': '2.3.2', 'appStoreState': 'PREPARE_FOR_SUBMISSION'}}
        self.history = [{'id': 'previous', 'attributes': {'platform': 'MAC_OS',
            'versionString': '2.3.1', 'appStoreState': 'READY_FOR_SALE'}}]
        self.localizations = [
            {'id': locale, 'attributes': {'locale': locale, 'whatsNew': 'Bug fixes'}}
            for locale in ('en-US', 'de-DE')]
        self.submissions = []
        self.items = []
        self.paged = patch.object(submit.client, 'paged', side_effect=self.pages).start()
        self.call = patch.object(submit.client, 'call', return_value=(200, {
            'data': {'attributes': {'version': '19'}}})).start()
        self.expect = patch.object(submit.client, 'expect', side_effect=self.write).start()
        # If an unmocked request slips through, fail before credentials or network access.
        patch.object(submit.client, 'token', side_effect=AssertionError('Live ASC access')).start()
        self.addCleanup(patch.stopall)

    def pages(self, path):
        if path == f'/v1/apps/{submit.APP}/appStoreVersions?limit=50':
            return [self.version, *self.history]
        if path == '/v1/appStoreVersions/target/appStoreVersionLocalizations?limit=50':
            return self.localizations
        platform = self.version['attributes']['platform']
        if path == f'/v1/reviewSubmissions?filter[app]={submit.APP}&filter[platform]={platform}&limit=20':
            return self.submissions
        if path == '/v1/reviewSubmissions/existing/items?include=appStoreVersion&limit=20':
            return self.items
        self.fail(f'Unexpected read: {path}')

    def write(self, method, path, body):
        self.assertIn(method, ('POST', 'PATCH'))
        if path == '/v1/reviewSubmissions':
            return {'data': {'id': 'created'}}
        return {}

    def existing(self, state='READY_FOR_REVIEW'):
        self.submissions = [{'id': 'existing', 'attributes': {'state': state}}]

    def linked_item(self, version_id='target', state='READY_FOR_REVIEW'):
        return {'id': 'item', 'attributes': {'state': state}, 'relationships': {
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version_id}}}}

    def run_submit(self, dry_run=False):
        output = io.StringIO()
        args = ['submit.py', '--platform', self.version['attributes']['platform'], '--build', '19']
        if dry_run:
            args.append('--dry-run')
        with patch.object(sys, 'argv', args), redirect_stdout(output):
            self.assertEqual(submit.main(), 0)
        return output.getvalue()

    def assert_blocked(self, message, dry_run=False):
        self.expect.reset_mock()
        with self.assertRaisesRegex(SystemExit, message):
            self.run_submit(dry_run)
        self.expect.assert_not_called()

    def test_first_platform_release_allows_absent_whats_new(self):
        for platform in ('MAC_OS', 'IOS'):
            for dry_run in (False, True):
                for state in ('PREPARE_FOR_SUBMISSION', 'REJECTED'):
                    with self.subTest(platform=platform, dry_run=dry_run, state=state):
                        self.expect.reset_mock()
                        self.version['attributes'].update(platform=platform, appStoreState=state)
                        # An approved release on another platform is not an update here.
                        self.history[0]['attributes']['platform'] = 'IOS' if platform == 'MAC_OS' else 'MAC_OS'
                        self.localizations = [{'id': 'en', 'attributes': {'locale': 'en-US'}}]
                        self.existing()
                        self.run_submit(dry_run)
                        self.assertEqual(self.expect.call_count, 0 if dry_run else 2)

    def test_later_update_requires_notes_even_if_version_is_one_point_zero(self):
        self.version['attributes']['versionString'] = '1.0'
        self.history[0]['attributes']['appStoreState'] = 'REPLACED_WITH_NEW_VERSION'
        self.localizations[0]['attributes'].pop('whatsNew')
        for dry_run in (False, True):
            self.assert_blocked('whatsNew.*en-US', dry_run)

    def test_uncertain_history_does_not_get_first_release_exemption(self):
        self.history = [{'id': 'unknown', 'attributes': {}}]
        self.localizations[0]['attributes'].pop('whatsNew')
        self.assert_blocked('whatsNew.*en-US')

    def test_history_read_failure_does_not_mutate(self):
        self.paged.side_effect = SystemExit('History unavailable')
        self.assert_blocked('History unavailable')

    def test_missing_localized_notes_never_mutates(self):
        for dry_run in (False, True):
            for notes in (None, '', ' \n\t'):
                for existing in (False, True):
                    with self.subTest(dry_run=dry_run, notes=notes, existing=existing):
                        self.submissions = []
                        if existing:
                            self.existing()
                        self.localizations[1]['attributes']['whatsNew'] = notes
                        self.assert_blocked('Missing localized whatsNew for: de-DE', dry_run)

    def test_absent_whats_new_and_no_localizations_are_blocked(self):
        del self.localizations[0]['attributes']['whatsNew']
        self.assert_blocked('en-US')
        self.localizations = []
        self.assert_blocked('No version localizations')

    def test_creates_attaches_then_submits(self):
        self.run_submit()
        writes = self.expect.call_args_list
        self.assertEqual([c.args[:2] for c in writes], [
            ('POST', '/v1/reviewSubmissions'),
            ('POST', '/v1/reviewSubmissionItems'),
            ('PATCH', '/v1/reviewSubmissions/created')])
        relationships = writes[1].args[2]['data']['relationships']
        self.assertEqual(relationships['appStoreVersion']['data']['id'], 'target')
        self.assertEqual(relationships['reviewSubmission']['data']['id'], 'created')
        self.assertEqual(writes[2].args[2]['data']['attributes'], {'submitted': True})

    def test_empty_ready_submission_is_attached_before_submitting(self):
        self.existing()
        self.run_submit()
        writes = self.expect.call_args_list
        self.assertEqual([c.args[:2] for c in writes], [
            ('POST', '/v1/reviewSubmissionItems'),
            ('PATCH', '/v1/reviewSubmissions/existing')])
        relationships = writes[0].args[2]['data']['relationships']
        self.assertEqual(relationships['appStoreVersion']['data']['id'], 'target')
        self.assertEqual(relationships['reviewSubmission']['data']['id'], 'existing')

    def test_matching_ready_submission_does_not_duplicate_item(self):
        self.existing()
        self.items = [self.linked_item()]
        self.run_submit()
        self.assertEqual(self.expect.call_count, 1)
        self.assertEqual(self.expect.call_args.args[1], '/v1/reviewSubmissions/existing')

    def test_rejected_resubmission_resolves_only_its_item(self):
        for state in ('REJECTED', 'UNRESOLVED_ISSUES'):
            with self.subTest(state=state):
                self.expect.reset_mock()
                self.version['attributes']['appStoreState'] = 'REJECTED'
                self.existing('UNRESOLVED_ISSUES')
                self.items = [self.linked_item(state=state)]
                self.run_submit()
                writes = self.expect.call_args_list
                self.assertEqual([c.args[:2] for c in writes], [
                    ('PATCH', '/v1/reviewSubmissionItems/item'),
                    ('PATCH', '/v1/reviewSubmissions/existing')])
                self.assertEqual(writes[0].args[2]['data']['attributes'], {'resolved': True})

    def test_unrelated_missing_and_multiple_items_are_blocked(self):
        self.existing('UNRESOLVED_ISSUES')
        for items in ([self.linked_item('other', 'REJECTED')],
                      [{'id': 'event', 'attributes': {'state': 'REJECTED'}, 'relationships': {}}],
                      [self.linked_item(state='REJECTED'), self.linked_item('other')],
                      [self.linked_item(), self.linked_item()]):
            self.items = items
            for dry_run in (False, True):
                with self.subTest(items=items, dry_run=dry_run):
                    self.assert_blocked('unrelated or ambiguous', dry_run)

    def test_multiple_active_submissions_are_blocked(self):
        self.existing()
        self.submissions.append({'id': 'other', 'attributes': {'state': 'READY_FOR_REVIEW'}})
        for dry_run in (False, True):
            self.assert_blocked('Ambiguous active', dry_run)

    def test_empty_unresolved_or_pending_submission_is_blocked(self):
        for state in ('UNRESOLVED_ISSUES', 'WAITING_FOR_REVIEW', 'IN_REVIEW'):
            self.existing(state)
            for dry_run in (False, True):
                with self.subTest(state=state, dry_run=dry_run):
                    self.assert_blocked('not READY_FOR_REVIEW|refusing to alter', dry_run)

    def test_dry_run_inspects_and_describes_every_safe_path_without_writes(self):
        for state, items, description in (
                (None, [], 'create a submission'),
                ('READY_FOR_REVIEW', [], 'attach this version to empty submission existing'),
                ('READY_FOR_REVIEW', [self.linked_item()], 'resubmit existing'),
                ('UNRESOLVED_ISSUES', [self.linked_item(state='REJECTED')], 'resubmit existing')):
            with self.subTest(state=state):
                self.submissions = []
                if state:
                    self.existing(state)
                self.items = items
                self.assertIn(description, self.run_submit(dry_run=True))
                self.expect.assert_not_called()
                if state:
                    self.assertTrue(any('/items?include=appStoreVersion' in c.args[0]
                                        for c in self.paged.call_args_list))

    def test_ios_uses_the_same_metadata_and_recovery_guards(self):
        self.version['attributes']['platform'] = 'IOS'
        self.history[0]['attributes']['platform'] = 'IOS'
        self.existing()
        self.localizations[0]['attributes']['whatsNew'] = None
        self.assert_blocked('en-US')
        self.localizations[0]['attributes']['whatsNew'] = 'Bug fixes'
        self.run_submit()
        self.assertEqual(self.expect.call_count, 2)
        self.assertEqual(self.expect.call_args_list[0].args[1], '/v1/reviewSubmissionItems')

    def test_failed_item_attachment_does_not_submit_empty_submission(self):
        self.existing()
        self.expect.side_effect = SystemExit('Attachment refused')
        with self.assertRaisesRegex(SystemExit, 'Attachment refused'):
            self.run_submit()
        self.assertEqual(self.expect.call_count, 1)
        self.assertEqual(self.expect.call_args.args[1], '/v1/reviewSubmissionItems')

    def test_failed_item_inspection_does_not_mutate(self):
        self.existing()
        original = self.pages
        def pages(path):
            if '/items?' in path:
                raise SystemExit('Unable to read items')
            return original(path)
        self.paged.side_effect = pages
        self.assert_blocked('Unable to read items')

    def test_wrong_build_is_blocked_before_writes(self):
        self.call.return_value = (200, {'data': {'attributes': {'version': '18'}}})
        self.assert_blocked('not 19')


if __name__ == '__main__':
    unittest.main()
