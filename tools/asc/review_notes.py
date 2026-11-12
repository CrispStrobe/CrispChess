#!/usr/bin/env python3
"""Append release-specific review notes to the version carrying a checked build."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]
EDITABLE = ("PREPARE_FOR_SUBMISSION", "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["IOS", "MAC_OS"], required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--notes-file", type=pathlib.Path, required=True)
    args = parser.parse_args()
    note = args.notes_file.read_text().strip()
    if not note:
        raise SystemExit("review note is empty")
    versions = [version for version in client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
                if version["attributes"].get("platform") == args.platform
                and version["attributes"].get("appStoreState") in EDITABLE]
    if len(versions) != 1:
        raise SystemExit(f"expected one editable {args.platform} version, found {len(versions)}")
    version = versions[0]
    build = client.expect("GET", f"/v1/appStoreVersions/{version['id']}/build").get("data") or {}
    if build.get("attributes", {}).get("version") != args.build:
        raise SystemExit(f"{args.platform} version does not carry build {args.build}")
    detail = client.expect("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]
    existing = detail["attributes"].get("notes") or ""
    if note in existing:
        print("App Review notes already contain the release explanation")
        return 0
    updated = (existing.rstrip() + "\n\n" + note).strip()
    client.expect("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {
        "type": "appStoreReviewDetails", "id": detail["id"],
        "attributes": {"notes": updated}}})
    print(f"App Review notes updated for {args.platform} build {args.build}; existing notes preserved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
