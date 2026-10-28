#!/usr/bin/env python3
"""Check a built Mac app's installed name, identity, executable, and version."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
from xml.parsers.expat import ExpatError

from release_version import read_version


def _read_localized_names(path: Path) -> dict:
    """Read app-name overrides in compiled or UTF-8/UTF-16 strings files."""
    raw = path.read_bytes()
    try:
        value = plistlib.loads(raw)
    except plistlib.InvalidFileException:
        text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff"))
                          else "utf-8-sig")
        # Tokenize before reading keys: comments and quoted permission text
        # may themselves mention CFBundleName and must not become overrides.
        lexer = re.compile(r'\s+|//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\[\s\S]|[^"\\])*"|[\w.:-]+|[=;]')
        tokens = []
        position = 0
        while position < len(text):
            match = lexer.match(text, position)
            if match is None:
                raise ValueError("invalid strings file syntax")
            token = match.group()
            if not token.isspace() and not token.startswith(("//", "/*")):
                tokens.append(token)
            position = match.end()
        value = {}
        if len(tokens) % 4:
            raise ValueError("invalid strings file entry")
        for offset in range(0, len(tokens), 4):
            key, equals, name, semicolon = tokens[offset:offset + 4]
            if equals != "=" or semicolon != ";":
                raise ValueError("invalid strings file entry")
            key = json.loads(key) if key.startswith('"') else key
            if key in ("CFBundleName", "CFBundleDisplayName"):
                # OpenStep strings spell Unicode escapes with a capital U.
                name = re.sub(r'\\U([0-9a-fA-F]{4})', r'\\u\1', name)
                value[key] = json.loads(name) if name.startswith('"') else name
    if not isinstance(value, dict):
        raise ValueError("strings file must contain a dictionary")
    return value


def verify_app(app: Path, version: str, build: str) -> None:
    if app.name != "CrispChess.app" or not app.is_dir():
        raise ValueError(f"expected a built CrispChess.app at {app}")
    try:
        with (app / "Contents/Info.plist").open("rb") as source:
            info = plistlib.load(source)
    except (OSError, ValueError, ExpatError) as error:
        raise ValueError(f"cannot read {app}/Contents/Info.plist: {error}") from error
    if not isinstance(info, dict):
        raise ValueError("Info.plist must contain a dictionary")
    expected = {
        "CFBundleName": "CrispChess",
        "CFBundleDisplayName": "CrispChess",
        "CFBundleExecutable": "CrispChess",
        "CFBundleIdentifier": "com.crispstrobe.crispchess",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"{key}: expected {value!r}, got {info.get(key)!r}")
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable:
        raise ValueError("CFBundleExecutable must name the app executable")
    path = app / "Contents/MacOS" / executable
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"app executable is missing or not executable: {path}")
    for strings in sorted((app / "Contents/Resources").glob("*.lproj/InfoPlist.strings")):
        try:
            localized = _read_localized_names(strings)
        except (OSError, ValueError, ExpatError) as error:
            raise ValueError(f"cannot read {strings}: {error}") from error
        for key in ("CFBundleName", "CFBundleDisplayName"):
            if key in localized and localized[key] != "CrispChess":
                raise ValueError(f"{strings}: {key}: expected 'CrispChess', got {localized[key]!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="path to the built CrispChess.app")
    args = parser.parse_args()
    try:
        version, build = read_version()
        verify_app(args.app, version, build)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Mac app validation failed: {error}\n")
    print(f"Verified CrispChess {version} ({build}): {args.app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
