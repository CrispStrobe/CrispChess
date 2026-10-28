"""Regression checks for Mac releases; all App Store API calls are mocked."""

from contextlib import redirect_stdout
import io
import os
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
import store  # noqa: E402
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


class AdHocSigningTests(unittest.TestCase):
    def test_desktop_signing_preserves_permissions_without_provisioning_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            app = directory / 'Desktop release/CrispChess.app'
            (app / 'Contents').mkdir(parents=True)
            profile = app / 'Contents/embedded.provisionprofile'
            profile.write_text('distribution profile')
            commands = directory / 'bin'
            commands.mkdir()
            codesign = commands / 'codesign'
            codesign.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
if '--entitlements' in sys.argv:
    source = pathlib.Path(sys.argv[sys.argv.index('--entitlements') + 1])
    pathlib.Path(os.environ['SIGNED_ENTITLEMENTS']).write_bytes(source.read_bytes())
''')
            codesign.chmod(0o755)
            result = directory / 'signed.plist'
            source = TOOLS.parent / 'macos/Runner/Release.entitlements'
            original = source.read_bytes()
            subprocess.run(['bash', str(TOOLS.parent / 'tool/sign_macos_adhoc.sh'), str(app)],
                           check=True, env=os.environ | {
                               'PATH': str(commands) + os.pathsep + os.environ['PATH'],
                               'SIGNED_ENTITLEMENTS': str(result)})
            self.assertEqual(plistlib.loads(result.read_bytes()), {
                'com.apple.security.app-sandbox': True,
                'com.apple.security.device.audio-input': True,
                'com.apple.security.network.client': True,
            })
            self.assertFalse(profile.exists())
            self.assertEqual(source.read_bytes(), original)

    def test_signing_failure_stops_the_release(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = Path(directory)
            codesign = commands / 'codesign'
            codesign.write_text('#!/bin/sh\nexit 7\n')
            codesign.chmod(0o755)
            result = subprocess.run(
                ['bash', str(TOOLS.parent / 'tool/sign_macos_adhoc.sh'), str(commands / 'CrispChess.app')],
                env=os.environ | {'PATH': str(commands) + os.pathsep + os.environ['PATH']},
                capture_output=True)
            self.assertEqual(result.returncode, 7)


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


class StoreBuildTests(unittest.TestCase):
    def setUp(self):
        self.versions = [{"id": "mac-version", "attributes": {
            "platform": "MAC_OS", "appStoreState": "REJECTED", "versionString": "2.3.1"}}]
        self.builds = [{"id": platform, "attributes": {
            "version": "17", "processingState": "VALID"}} for platform in ("IOS", "MAC_OS")]
        self.paged = patch.object(store.client, "paged", side_effect=lambda path:
                                 self.versions if "appStoreVersions?" in path else self.builds).start()
        patch.object(store.client, "call", side_effect=lambda method, path:
                     (200, {"data": {"attributes": {
                         "platform": path.split('/')[3], "version": "2.3.1"}}})).start()
        self.expect = patch.object(store.client, "expect").start()
        self.age = patch.object(store, "complete_age_rating").start()
        self.price = patch.object(store, "ensure_free_price").start()
        self.addCleanup(patch.stopall)

    def run_helper(self, extra=()):
        args = ["store.py", "--platform", "MAC_OS", "--build", "17", *extra]
        with patch.object(sys, "argv", args), redirect_stdout(io.StringIO()):
            return store.main()

    def test_attach_only_preserves_shared_metadata_and_selects_mac_build(self):
        self.assertEqual(self.run_helper(["--attach-only"]), 0)
        self.age.assert_not_called()
        self.price.assert_not_called()
        self.expect.assert_called_once_with(
            "PATCH", "/v1/appStoreVersions/mac-version/relationships/build",
            {"data": {"type": "builds", "id": "MAC_OS"}})

    def test_default_still_prepares_metadata(self):
        self.assertEqual(self.run_helper(), 0)
        self.age.assert_called_once_with()
        self.price.assert_called_once_with()

    def test_attach_only_refuses_an_ios_build_with_the_same_number(self):
        self.builds = self.builds[:1]
        with self.assertRaises(SystemExit):
            self.run_helper(["--attach-only"])
        self.expect.assert_not_called()

    def test_explicit_build_number_is_required(self):
        with patch.object(sys, "argv", ["store.py"]), redirect_stdout(io.StringIO()), patch('sys.stderr', io.StringIO()):
            with self.assertRaises(SystemExit):
                store.main()
        self.paged.assert_not_called()


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

    def test_rejects_runner_executable_even_when_it_exists(self):
        self.executable.rename(self.executable.with_name("Runner"))
        self.write_info(self.info | {"CFBundleExecutable": "Runner"})
        with self.assertRaisesRegex(ValueError, "CFBundleExecutable"):
            verify_app(self.app, "3.2.1", "42")

    def localized_names(self, locale):
        path = self.app / "Contents/Resources" / f"{locale}.lproj/InfoPlist.strings"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def test_accepts_localized_plist_names_and_inherited_names(self):
        for locale, fmt in (("en", plistlib.FMT_XML), ("de", plistlib.FMT_BINARY)):
            self.localized_names(locale).write_bytes(plistlib.dumps({
                "CFBundleName": "CrispChess", "CFBundleDisplayName": "CrispChess",
            }, fmt=fmt))
        self.localized_names("fr").write_text('"NSMicrophoneUsageDescription" = "Speak a move";')
        verify_app(self.app, "3.2.1", "42")

    def test_accepts_utf8_and_utf16_names_without_reading_comments_as_overrides(self):
        text = r'''/* CFBundleName = "Runner"; */
"CFBundleName" = "\U0043rispChess";
CFBundleDisplayName = "CrispChess";
"NSMicrophoneUsageDescription" = "See https://example.com/CFBundleName";
// CFBundleDisplayName = "Runner";
'''
        for locale, encoding in (("en", "utf-8-sig"), ("de", "utf-16")):
            self.localized_names(locale).write_text(text, encoding=encoding)
        verify_app(self.app, "3.2.1", "42")

    def test_rejects_localized_name_mismatch_in_every_supported_format(self):
        for key in ("CFBundleName", "CFBundleDisplayName"):
            for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY, "utf-8", "utf-16"):
                with self.subTest(key=key, fmt=fmt):
                    path = self.localized_names("de")
                    if isinstance(fmt, str):
                        path.write_text(f'"{key}" = "Runner";', encoding=fmt)
                    else:
                        path.write_bytes(plistlib.dumps({key: "Runner"}, fmt=fmt))
                    with self.assertRaisesRegex(ValueError, rf"de.lproj.*{key}"):
                        verify_app(self.app, "3.2.1", "42")

    def test_rejects_unreadable_localized_names(self):
        path = self.localized_names("en")
        for content in (b'"CFBundleName" = "CrispChess"', b'\xffbad',
                        plistlib.dumps(["Runner"]), b'"CFBundleName" ? "Runner";'):
            with self.subTest(content=content):
                path.write_bytes(content)
                with self.assertRaisesRegex(ValueError, "cannot read.*en.lproj"):
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
