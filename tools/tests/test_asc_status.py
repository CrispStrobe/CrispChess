"""Release selection is read-only and never reuses an uploaded build number."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path[:0] = [str(Path(__file__).resolve().parents[1] / 'asc')]
import status


class StatusTests(unittest.TestCase):
    def setUp(self):
        self.versions = [{'id': 'mac', 'attributes': {'platform': 'MAC_OS',
            'versionString': '2.3.1', 'appStoreState': 'WAITING_FOR_REVIEW'}}]
        self.builds = [{'id': 'newest', 'attributes': {'version': '18', 'processingState': 'VALID'},
            'relationships': {'preReleaseVersion': {'data': {'id': 'mac-release'}}}}]
        self.paged = patch.object(status.client, 'paged', side_effect=lambda _: self.versions).start()
        self.call = patch.object(status.client, 'call', return_value=(200, {'data': {
            'id': 'attached', 'attributes': {'version': '17'}}})).start()
        self.expect = patch.object(status.client, 'expect', side_effect=self.response).start()
        patch.object(status, 'read_version', return_value=('2.3.1', '17')).start()
        self.addCleanup(patch.stopall)

    def response(self, method, path):
        self.assertEqual(method, 'GET')
        if 'preReleaseVersion' in path and '/builds/' in path:
            return {'data': {'attributes': {'platform': 'MAC_OS', 'version': '2.3.1'}}}
        return {'data': self.builds, 'included': [{'id': 'mac-release', 'type': 'preReleaseVersions',
            'attributes': {'platform': 'MAC_OS', 'version': '2.3.1'}}]}

    def test_pending_replacement_keeps_marketing_version_and_uses_unused_build(self):
        result = status.release_status('MAC_OS')
        self.assertEqual(result['candidate'], {'version': '2.3.1', 'build': '19'})
        self.assertEqual(result['versions'][0]['build'], '17')
        self.call.assert_called_once_with('GET', '/v1/appStoreVersions/mac/build')

    def test_approved_release_gets_new_patch_version(self):
        for state in ('READY_FOR_DISTRIBUTION', 'PENDING_DEVELOPER_RELEASE', 'PENDING_APPLE_RELEASE'):
            with self.subTest(state=state):
                self.versions[0]['attributes']['appStoreState'] = state
                self.assertEqual(status.release_status('MAC_OS')['candidate']['version'], '2.3.2')

    def test_ios_build_numbers_are_not_selected_for_mac(self):
        self.builds.append({'id': 'ios', 'attributes': {'version': '99', 'processingState': 'VALID'},
            'relationships': {'preReleaseVersion': {'data': {'id': 'ios-release'}}}})
        def response(method, path):
            doc = self.response(method, path)
            doc['included'].append({'id': 'ios-release', 'type': 'preReleaseVersions',
                'attributes': {'platform': 'IOS', 'version': '2.3.1'}})
            return doc
        self.expect.side_effect = response
        self.assertEqual(status.release_status('MAC_OS')['candidate']['build'], '19')

    def test_ambiguous_editable_versions_are_rejected(self):
        self.versions[0]['attributes']['appStoreState'] = 'REJECTED'
        self.versions.append({'id': 'other', 'attributes': {'platform': 'MAC_OS',
            'versionString': '2.3.2', 'appStoreState': 'PREPARE_FOR_SUBMISSION'}})
        with self.assertRaisesRegex(ValueError, 'Ambiguous'):
            status.release_status('MAC_OS')

    def test_failed_attachment_lookup_is_not_treated_as_missing(self):
        self.call.return_value = (403, {})
        with self.assertRaisesRegex(ValueError, 'HTTP 403'):
            status.release_status('MAC_OS')
