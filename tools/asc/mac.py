#!/usr/bin/env python3
"""Ensure an editable macOS App Store version exists."""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]
VERSION = "2.1.0"


def main() -> int:
    versions = client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
    mac_versions = [version for version in versions
                    if version["attributes"].get("platform") == "MAC_OS"]
    editable = [version for version in mac_versions if
                version["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"]
    if len(editable) > 1:
        raise SystemExit(f"expected at most one editable macOS version, found {len(editable)}")
    if editable:
        version = editable[0]
        if version["attributes"].get("versionString") != VERSION:
            client.expect("PATCH", f"/v1/appStoreVersions/{version['id']}", {
                "data": {"type": "appStoreVersions", "id": version["id"],
                         "attributes": {"versionString": VERSION}}})
        print(f"macOS version: {VERSION} ready")
        return 0
    if mac_versions:
        raise SystemExit("macOS has versions but none is editable")
    client.expect("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "MAC_OS", "versionString": VERSION},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
    }})
    print(f"macOS version: {VERSION} created")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
