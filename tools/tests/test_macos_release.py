"""Regression checks for Mac releases; all App Store API calls are mocked."""

from contextlib import redirect_stdout
import io
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(TOOLS), str(TOOLS / "asc")]

import mac  # noqa: E402
from release_version import read_version  # noqa: E402
from verify_macos_app import verify_app  # noqa: E402


class VersionTests(unittest.TestCase):
    def test_reads_pubspec_formats(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            for value in ("3.2.1+42", "'3.2.1+42'", '"3.2.1+42" # release'):
                with self.subTest(value=value):
                    pubspec.write_text(f"name: crispchess\nversion: {value}\n")
                    self.assertEqual(read_version(pubspec), ("3.2.1", "42"))

    def test_rejects_missing_or_invalid_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            for value in ("name: crispchess", "version: 3.2.1", "version: 3.2.1+abc"):
                with self.subTest(value=value):
                    pubspec.write_text(value)
                    with self.assertRaises(ValueError):
                        read_version(pubspec)


class MacVersionTests(unittest.TestCase):
    def setUp(self):
        self.paged = patch.object(mac.client, "paged").start()
        self.expect = patch.object(mac.client, "expect").start()
        patch.object(mac, "read_version", return_value=("3.2.1", "42")).start()
        self.addCleanup(patch.stopall)

    def version(self, state, version="3.2.1", platform="MAC_OS"):
        return {"id": "existing", "attributes": {
            "platform": platform, "appStoreState": state, "versionString": version}}

    def run_helper(self):
        with redirect_stdout(io.StringIO()):
            return mac.main()

    def test_reuses_each_editable_state_without_writing(self):
        for state in mac.EDITABLE:
            with self.subTest(state=state):
                self.paged.return_value = [self.version(state)]
                self.assertEqual(self.run_helper(), 0)
                self.expect.assert_not_called()

    def test_updates_rejected_version_in_place(self):
        self.paged.return_value = [self.version("REJECTED", "2.1.0")]
        self.assertEqual(self.run_helper(), 0)
        self.expect.assert_called_once_with("PATCH", "/v1/appStoreVersions/existing", {
            "data": {"type": "appStoreVersions", "id": "existing",
                     "attributes": {"versionString": "3.2.1"}}})

    def test_creates_first_mac_version_and_ignores_ios(self):
        for versions in ([], [self.version("REJECTED", platform="IOS")]):
            with self.subTest(versions=versions):
                self.expect.reset_mock()
                self.paged.return_value = versions
                self.assertEqual(self.run_helper(), 0)
                method, endpoint, body = self.expect.call_args.args
                self.assertEqual((method, endpoint), ("POST", "/v1/appStoreVersions"))
                self.assertEqual(body["data"]["attributes"], {
                    "platform": "MAC_OS", "versionString": "3.2.1"})

    def test_refuses_ambiguous_or_noneditable_mac_versions(self):
        for versions in ([self.version("WAITING_FOR_REVIEW")],
                         [self.version("REJECTED"), self.version("PREPARE_FOR_SUBMISSION")]):
            with self.subTest(versions=versions):
                self.paged.return_value = versions
                with self.assertRaises(SystemExit):
                    self.run_helper()
                self.expect.assert_not_called()


class AppValidationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.app = Path(directory.name) / "CrispChess.app"
        self.executable = self.app / "Contents/MacOS/CrispChess"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_text("#!/bin/sh\nexit 0\n")
        self.executable.chmod(0o755)
        self.info = {
            "CFBundleName": "CrispChess", "CFBundleDisplayName": "CrispChess",
            "CFBundleIdentifier": "com.crispstrobe.crispchess",
            "CFBundleExecutable": "CrispChess",
            "CFBundleShortVersionString": "3.2.1", "CFBundleVersion": "42",
        }
        self.write_info(self.info)

    def write_info(self, info):
        with (self.app / "Contents/Info.plist").open("wb") as target:
            plistlib.dump(info, target)

    def test_accepts_correct_app(self):
        verify_app(self.app, "3.2.1", "42")

    def test_rejects_wrong_or_missing_identity_and_version(self):
        for key in ("CFBundleName", "CFBundleDisplayName", "CFBundleIdentifier",
                    "CFBundleShortVersionString", "CFBundleVersion"):
            for replacement in ("Runner", None):
                with self.subTest(key=key, replacement=replacement):
                    info = self.info.copy()
                    if replacement is None:
                        info.pop(key)
                    else:
                        info[key] = replacement
                    self.write_info(info)
                    with self.assertRaisesRegex(ValueError, key):
                        verify_app(self.app, "3.2.1", "42")

    def test_rejects_missing_or_nonexecutable_binary(self):
        self.executable.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "not executable"):
            verify_app(self.app, "3.2.1", "42")
        self.executable.unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            verify_app(self.app, "3.2.1", "42")

    def test_rejects_invalid_executable_name(self):
        self.write_info(self.info | {"CFBundleExecutable": "../CrispChess"})
        with self.assertRaisesRegex(ValueError, "CFBundleExecutable"):
            verify_app(self.app, "3.2.1", "42")

    def test_rejects_wrong_bundle_filename(self):
        runner = self.app.with_name("Runner.app")
        self.app.rename(runner)
        with self.assertRaisesRegex(ValueError, "CrispChess.app"):
            verify_app(runner, "3.2.1", "42")

    def test_rejects_missing_or_malformed_plist(self):
        plist = self.app / "Contents/Info.plist"
        for content in (None, b"broken", b'<?xml version="1.0"?><plist><dict>'):
            with self.subTest(content=content):
                if content is None:
                    plist.unlink()
                else:
                    plist.write_bytes(content)
                with self.assertRaisesRegex(ValueError, "cannot read"):
                    verify_app(self.app, "3.2.1", "42")

    def test_cli_uses_repository_version_from_another_directory(self):
        version, build = read_version()
        self.write_info(self.info | {
            "CFBundleShortVersionString": version, "CFBundleVersion": build})
        result = subprocess.run([sys.executable, str(TOOLS / "verify_macos_app.py"),
                                 str(self.app)], cwd=self.app.parent,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Verified CrispChess {version} ({build})", result.stdout)


if __name__ == "__main__":
    unittest.main()
