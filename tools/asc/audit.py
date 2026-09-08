#!/usr/bin/env python3
"""Read-only audit of CrispChess's live App Store Connect state."""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
META = json.loads((HERE / "metadata.json").read_text())
APP = META["appId"]


def attrs(item: dict | None, *names: str) -> dict:
    source = (item or {}).get("attributes", {})
    return {name: source.get(name) for name in names}


def main() -> int:
    app = client.expect("GET", f"/v1/apps/{APP}")["data"]
    print("app", APP, attrs(app, "name", "bundleId", "primaryLocale",
                             "contentRightsDeclaration"))

    print("\nversions")
    for version in client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50"):
        platform = version["attributes"].get("platform")
        print(" ", version["id"], attrs(version, "platform", "versionString",
                                           "appStoreState", "copyright"))
        status, build = client.call("GET", f"/v1/appStoreVersions/{version['id']}/build")
        build_data = build.get("data") or {}
        print("    build", status, build_data.get("id"),
              attrs(build_data, "version", "processingState", "uploadedDate"))
        status, review = client.call(
            "GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
        print("    review", status, attrs(review.get("data"), "contactEmail",
                                            "demoAccountRequired"))
        for loc in client.paged(
            f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50"
        ):
            filled = [name for name in ("description", "keywords", "supportUrl",
                                        "marketingUrl", "promotionalText")
                      if loc.get("attributes", {}).get(name)]
            counts = {}
            for screenshot_set in client.paged(
                f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50"
            ):
                shots = client.paged(
                    f"/v1/appScreenshotSets/{screenshot_set['id']}/appScreenshots?limit=50"
                )
                counts[screenshot_set["attributes"].get("screenshotDisplayType")] = len(shots)
            print("   ", platform, loc["attributes"].get("locale"),
                  "fields", filled, "screenshots", counts)

    print("\nbuilds")
    builds = client.paged(f"/v1/apps/{APP}/builds?limit=50")
    builds.sort(key=lambda item: item["attributes"].get("uploadedDate") or "", reverse=True)
    for build in builds[:15]:
        status, release = client.call("GET", f"/v1/builds/{build['id']}/preReleaseVersion")
        platform = attrs(release.get("data"), "platform").get("platform") if status == 200 else None
        print(" ", build["id"], platform,
              attrs(build, "version", "uploadedDate", "processingState",
                    "usesNonExemptEncryption", "iconAssetToken"))

    print("\napp info")
    for info in client.paged(f"/v1/apps/{APP}/appInfos?limit=50"):
        print(" ", info["id"], attrs(info, "appStoreState"))
        for loc in client.paged(f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50"):
            print("   ", attrs(loc, "locale", "name", "subtitle", "privacyPolicyUrl"))
        status, rating = client.call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
        print("    age rating", status, attrs(rating.get("data"), "ageRatingOverride"))

    print("\nbeta")
    for loc in client.paged(f"/v1/apps/{APP}/betaAppLocalizations?limit=50"):
        print(" ", attrs(loc, "locale", "description", "feedbackEmail"))
    for group in client.paged(f"/v1/apps/{APP}/betaGroups?limit=50"):
        builds = client.paged(f"/v1/betaGroups/{group['id']}/builds?limit=50")
        print(" ", group["id"], attrs(group, "name", "isInternalGroup",
                                        "publicLinkEnabled", "publicLink"),
              "builds", [(b["id"], b["attributes"].get("version")) for b in builds])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
