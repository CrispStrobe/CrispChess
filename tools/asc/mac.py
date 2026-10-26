#!/usr/bin/env python3
"""Ensure an editable macOS App Store version exists."""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from release_version import read_version  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]
EDITABLE = ("PREPARE_FOR_SUBMISSION", "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED")


def main() -> int:
    release_version, _ = read_version()
    versions = client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
    mac_versions = [version for version in versions
                    if version["attributes"].get("platform") == "MAC_OS"]
    editable = [version for version in mac_versions if
                version["attributes"].get("appStoreState") in EDITABLE]
    if len(editable) > 1:
        raise SystemExit(f"expected at most one editable macOS version, found {len(editable)}")
    if editable:
        version = editable[0]
        if version["attributes"].get("versionString") != release_version:
            client.expect("PATCH", f"/v1/appStoreVersions/{version['id']}", {
                "data": {"type": "appStoreVersions", "id": version["id"],
                         "attributes": {"versionString": release_version}}})
        print(f"macOS version: {release_version} ready")
        return 0
    if mac_versions:
        raise SystemExit("macOS has versions but none is editable")
    client.expect("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "MAC_OS", "versionString": release_version},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
    }})
    print(f"macOS version: {release_version} created")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
