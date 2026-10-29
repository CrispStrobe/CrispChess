from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_macos_smoke import verify_log

class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.log = Path(self.directory.name) / 'app.log'
        self.clean = 'CrispChess first frame rendered\n[CrispChess] Engine state: EngineState.ready\n'

    def test_accepts_frame_and_ready_engine(self):
        self.log.write_text(self.clean)
        verify_log(self.log)

    def test_rejects_the_archived_startup_failure_even_with_a_live_engine(self):
        self.log.write_text(self.clean + '[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Null check operator used on a null value\n')
        with self.assertRaisesRegex(ValueError, 'runtime failure'):
            verify_log(self.log)

    def test_rejects_missing_frame(self):
        self.log.write_text('[CrispChess] Engine state: EngineState.ready\n')
        with self.assertRaisesRegex(ValueError, 'first frame'):
            verify_log(self.log)

    def test_rejects_an_unready_opponent(self):
        self.log.write_text('CrispChess first frame rendered\n')
        with self.assertRaisesRegex(ValueError, 'opponent'):
            verify_log(self.log)

    def test_requires_the_requested_locale_in_the_render_marker(self):
        self.log.write_text('CrispChess first frame rendered; locale=de\n' + self.clean)
        verify_log(self.log, 'de')
        with self.assertRaisesRegex(ValueError, 'requested locale en'):
            verify_log(self.log, 'en')
