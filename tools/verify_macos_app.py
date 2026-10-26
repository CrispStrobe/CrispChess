#!/usr/bin/env python3
"""Check a built Mac app's installed name, identity, executable, and version."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
from xml.parsers.expat import ExpatError

from release_version import read_version


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
