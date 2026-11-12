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
                        patch.object(new_release.client, 'paged', return_value=[]),
                        patch.object(new_release.client, 'expect', return_value={}),
                        patch.object(new_release, 'invoke')]
        self.mocks = [p.start() for p in self.patches]
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
        self.mocks[2].return_value = [{'attributes': {'state': 'READY_FOR_REVIEW'}}]
        with self.assertRaises(ValueError): self.run_release()
        self.mocks[3].assert_not_called()

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
