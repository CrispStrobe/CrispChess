#!/usr/bin/env python3
"""Upload and optionally replace App Store screenshot sets from a manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]
PLATFORM = {"APP_IPHONE_67": "IOS", "APP_IPAD_PRO_3GEN_129": "IOS",
            "APP_DESKTOP": "MAC_OS"}


def localisation(platform: str, locale: str) -> str:
    for version in client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50"):
        if version["attributes"].get("platform") != platform:
            continue
        for loc in client.paged(
            f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50"
        ):
            if loc["attributes"].get("locale") == locale:
                return loc["id"]
    raise SystemExit(f"no {platform} {locale} version localisation")


def put(operation: dict, blob: bytes) -> None:
    headers = {h["name"]: h["value"] for h in operation.get("requestHeaders", [])}
    request = urllib.request.Request(operation["url"], data=blob,
                                     method=operation.get("method", "PUT"), headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status not in (200, 201, 204):
                raise RuntimeError(f"upload returned {response.status}")
        return
    except Exception as error:
        print(f"urllib upload failed ({error}); retrying with curl")
    command = ["curl", "-fsS", "-X", operation.get("method", "PUT"),
               "--data-binary", "@-", operation["url"]]
    for name, value in headers.items():
        command += ["-H", f"{name}: {value}"]
    subprocess.run(command, input=blob, check=True)


def upload(set_id: str, path: pathlib.Path) -> None:
    blob = path.read_bytes()
    result = client.expect("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": path.name, "fileSize": len(blob)},
        "relationships": {"appScreenshotSet": {"data": {
            "type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for operation in result["attributes"]["uploadOperations"]:
        offset = operation.get("offset", 0)
        put(operation, blob[offset:offset + operation.get("length", len(blob))])
    client.expect("PATCH", f"/v1/appScreenshots/{result['id']}", {"data": {
        "type": "appScreenshots", "id": result["id"], "attributes": {
            "uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
    for _ in range(30):
        state = client.expect("GET", f"/v1/appScreenshots/{result['id']}")["data"]["attributes"].get("assetDeliveryState", {})
        if state.get("state") == "UPLOAD_COMPLETE":
            print(path.name, "UPLOAD_COMPLETE")
            return
        if state.get("errors"):
            raise SystemExit(json.dumps(state["errors"]))
        time.sleep(4)
    raise SystemExit(f"timed out processing {path.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()
    root = pathlib.Path(args.directory)
    entries = json.loads((root / "manifest.json").read_text())
    groups: dict[tuple[str, str], list[pathlib.Path]] = {}
    for entry in entries:
        groups.setdefault((entry["locale"], entry["displayType"]), []).append(root / entry["name"])
    for (locale, display_type), paths in groups.items():
        platform = PLATFORM[display_type]
        loc_id = localisation(platform, locale)
        sets = {item["attributes"]["screenshotDisplayType"]: item for item in client.paged(
            f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=50")}
        if args.replace and display_type in sets:
            client.expect("DELETE", f"/v1/appScreenshotSets/{sets[display_type]['id']}", ok=(200, 204))
            sets.pop(display_type)
        if display_type not in sets:
            sets[display_type] = client.expect("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {
                    "screenshotDisplayType": display_type}, "relationships": {
                        "appStoreVersionLocalization": {"data": {
                            "type": "appStoreVersionLocalizations", "id": loc_id}}}}})["data"]
        print(display_type, locale)
        for path in paths:
            upload(sets[display_type]["id"], path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
