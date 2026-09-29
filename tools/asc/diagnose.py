#!/usr/bin/env python3
"""Read-only: why an iOS version cannot be submitted.

Checks what App Store Connect needs before it accepts a submission: every
screenshot fully processed, the attached build valid, and the open review
submission's items and what they point at.
"""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]


def main() -> int:
    for v in client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50"):
        a = v["attributes"]
        if a.get("platform") != "IOS":
            continue
        print("version", v["id"], a.get("versionString"), a.get("appStoreState"),
              "releaseType", a.get("releaseType"), "downloadable", a.get("downloadable"))
        status, build = client.call("GET", f"/v1/appStoreVersions/{v['id']}/build")
        b = (build.get("data") or {}).get("attributes", {})
        print("  build", b.get("version"), b.get("processingState"),
              "encryption", b.get("usesNonExemptEncryption"), "expired", b.get("expired"))
        for loc in client.paged(
                f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50"):
            for s in client.paged(
                    f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50"):
                shots = client.paged(f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=50")
                states = [x["attributes"].get("assetDeliveryState", {}).get("state") for x in shots]
                images = sum(1 for x in shots if x["attributes"].get("imageAsset"))
                print("  shots", loc["attributes"]["locale"],
                      s["attributes"]["screenshotDisplayType"], states, "with image", images)
    for sub in client.paged(f"/v1/reviewSubmissions?filter[app]={APP}&filter[platform]=IOS&limit=20"):
        print("submission", sub["id"], sub["attributes"])
        status, items = client.call(
            "GET", f"/v1/reviewSubmissions/{sub['id']}/items?include=appStoreVersion&limit=20")
        for item in items.get("data", []):
            rel = item.get("relationships", {}).get("appStoreVersion", {}).get("data")
            print("  item", item["id"], item["attributes"], "version", rel)
        for inc in items.get("included", []):
            print("  included", inc["type"], inc["id"], inc["attributes"].get("appStoreState"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
