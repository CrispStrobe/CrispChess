#!/usr/bin/env python3
"""Complete API-editable iOS submission fields and attach a valid build."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]


def query(path: str, **params: str) -> str:
    return f"{path}?{urllib.parse.urlencode(params)}"


def complete_age_rating() -> None:
    infos = client.paged(f"/v1/apps/{APP}/appInfos?limit=50")
    editable = [item for item in infos if item["attributes"].get("appStoreState")
                not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION")]
    if len(editable) != 1:
        raise SystemExit(f"expected one editable appInfo, found {len(editable)}")
    rating_id = editable[0]["id"]
    attributes = {
        "advertising": False, "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "contests": "NONE", "gambling": False, "gamblingSimulated": "NONE",
        "gunsOrOtherWeapons": "NONE", "healthOrWellnessTopics": False,
        "lootBox": False, "medicalOrTreatmentInformation": "NONE",
        "messagingAndChat": False, "parentalControls": False,
        "profanityOrCrudeHumor": "NONE", "ageAssurance": False,
        "sexualContentGraphicAndNudity": "NONE", "sexualContentOrNudity": "NONE",
        "socialMedia": False, "socialMediaAgeRestricted": False,
        "horrorOrFearThemes": "NONE", "matureOrSuggestiveThemes": "NONE",
        "unrestrictedWebAccess": False, "userGeneratedContent": False,
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        "violenceRealistic": "NONE",
    }
    client.expect("PATCH", f"/v1/ageRatingDeclarations/{rating_id}", {
        "data": {"type": "ageRatingDeclarations", "id": rating_id,
                 "attributes": attributes}})
    print("age rating: completed (4+ content)")


def ensure_free_price() -> None:
    status, schedule = client.call("GET", query(
        f"/v1/apps/{APP}/appPriceSchedule", include="manualPrices",
        **{"limit[manualPrices]": "50"}))
    if status == 404:
        points = client.paged(query(f"/v1/apps/{APP}/appPricePoints",
                                    **{"filter[territory]": "USA", "limit": "200"}))
        free = next((p for p in points if str(p["attributes"].get("customerPrice"))
                     in ("0", "0.0", "0.00")), None)
        if not free:
            raise SystemExit("Apple returned no free price point")
        client.expect("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": APP}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]} }},
            "included": [{"type": "appPrices", "id": "${price1}",
                          "attributes": {"startDate": None}, "relationships": {
                              "appPricePoint": {"data": {"type": "appPricePoints",
                                                          "id": free["id"]}}}}]})
        print("price: free schedule created")
        return
    if status != 200:
        raise SystemExit(f"price schedule -> HTTP {status}: {schedule}")
    schedule_id = schedule["data"]["id"]
    price_status, prices = client.call("GET", query(
        f"/v1/appPriceSchedules/{schedule_id}/manualPrices",
        include="appPricePoint", **{
            "fields[appPrices]": "appPricePoint,startDate,endDate",
            "fields[appPricePoints]": "customerPrice",
            "filter[territory]": "USA", "limit": "200"}))
    if price_status != 200:
        raise SystemExit(f"manual prices -> HTTP {price_status}: {prices}")
    values = [item.get("attributes", {}).get("customerPrice")
              for item in prices.get("included", [])
              if item.get("type") == "appPricePoints"]
    if not any(str(value) in ("0", "0.0", "0.00") for value in values):
        raise SystemExit(f"existing price schedule is not free: {values}")
    print("price: verified free", values)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="12", help="CFBundleVersion to attach")
    args = parser.parse_args()
    versions = client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
    editable = [v for v in versions if v["attributes"].get("platform") == "IOS" and
                v["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"]
    if len(editable) != 1:
        raise SystemExit(f"expected one editable iOS version, found {len(editable)}")
    builds = client.paged(query(f"/v1/apps/{APP}/builds", **{
        "filter[version]": args.build, "filter[processingState]": "VALID", "limit": "10"}))
    if len(builds) != 1:
        raise SystemExit(f"expected one valid build {args.build}, found {len(builds)}")
    build = builds[0]
    status, prerelease = client.call("GET", f"/v1/builds/{build['id']}/preReleaseVersion")
    if status != 200:
        raise SystemExit("build has no pre-release version")
    release_version = prerelease["data"]["attributes"]["version"]
    version = editable[0]
    if version["attributes"].get("versionString") != release_version:
        client.expect("PATCH", f"/v1/appStoreVersions/{version['id']}", {
            "data": {"type": "appStoreVersions", "id": version["id"],
                     "attributes": {"versionString": release_version}}})
        print(f"iOS version: changed to {release_version}")
    complete_age_rating()
    ensure_free_price()
    client.expect("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build", {
        "data": {"type": "builds", "id": build["id"]}})
    print(f"build: attached {release_version} ({args.build})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
