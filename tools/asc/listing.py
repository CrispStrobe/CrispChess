#!/usr/bin/env python3
"""Apply the version-controlled EN/DE App Store listing."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
META = json.loads((HERE / "metadata.json").read_text())
APP = META["appId"]
LOCALES = {META["primaryLocale"]: META["app"], **{
    locale: copy["app"] for locale, copy in META.get("locales", {}).items()
}}


def change(method: str, path: str, body: dict, label: str, dry_run: bool) -> None:
    if dry_run:
        print("would", label)
    else:
        client.expect(method, path, body)
        print(label)


def editable_info() -> dict:
    infos = client.paged(f"/v1/apps/{APP}/appInfos?limit=50")
    editable = [item for item in infos if item["attributes"].get("appStoreState")
                not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION")]
    if len(editable) != 1:
        raise SystemExit(f"expected one editable appInfo, found {len(editable)}")
    return editable[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    dry_run = args.dry_run

    change("PATCH", f"/v1/apps/{APP}", {
        "data": {"type": "apps", "id": APP, "attributes": {
            "contentRightsDeclaration": META["contentRightsDeclaration"]}}
    }, f"content rights: {META['contentRightsDeclaration']}", dry_run)

    info = editable_info()
    existing = {loc["attributes"]["locale"]: loc for loc in client.paged(
        f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50")}
    for locale, copy in LOCALES.items():
        attributes = {"name": copy["name"], "subtitle": copy["subtitle"],
                      "privacyPolicyUrl": copy.get("privacyPolicyUrl",
                                                    META["app"]["privacyPolicyUrl"])}
        if locale in existing:
            loc_id = existing[locale]["id"]
            change("PATCH", f"/v1/appInfoLocalizations/{loc_id}", {
                "data": {"type": "appInfoLocalizations", "id": loc_id,
                         "attributes": attributes}},
                f"app info {locale}: updated", dry_run)
        else:
            change("POST", "/v1/appInfoLocalizations", {
                "data": {"type": "appInfoLocalizations",
                         "attributes": {**attributes, "locale": locale},
                         "relationships": {"appInfo": {"data": {
                             "type": "appInfos", "id": info["id"]}}}}},
                f"app info {locale}: created", dry_run)

    app = META["app"]
    change("PATCH", f"/v1/appInfos/{info['id']}", {
        "data": {"type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories",
                                           "id": app["primaryCategory"]}},
            "primarySubcategoryOne": {"data": {"type": "appCategories",
                                                 "id": app["primarySubcategoryOne"]}},
            "secondaryCategory": {"data": {"type": "appCategories",
                                             "id": app["secondaryCategory"]}}}}
    }, (f"categories: {app['primaryCategory']} → {app['primarySubcategoryOne']} / "
        f"{app['secondaryCategory']}"), dry_run)

    versions = client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
    editable_versions = [v for v in versions if v["attributes"].get("appStoreState")
                         == "PREPARE_FOR_SUBMISSION"]
    if not editable_versions:
        raise SystemExit("no editable App Store version")
    for version in editable_versions:
        platform = version["attributes"]["platform"]
        locs = {loc["attributes"]["locale"]: loc for loc in client.paged(
            f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")}
        for locale, copy in LOCALES.items():
            attributes = {
                "description": copy["description"], "keywords": copy["keywords"],
                "supportUrl": app["supportUrl"], "marketingUrl": app["marketingUrl"],
                "promotionalText": copy["promotionalText"],
            }
            if locale in locs:
                loc_id = locs[locale]["id"]
                change("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id,
                             "attributes": attributes}},
                    f"{platform} listing {locale}: updated", dry_run)
            else:
                change("POST", "/v1/appStoreVersionLocalizations", {
                    "data": {"type": "appStoreVersionLocalizations",
                             "attributes": {**attributes, "locale": locale},
                             "relationships": {"appStoreVersion": {"data": {
                                 "type": "appStoreVersions", "id": version["id"]}}}}},
                    f"{platform} listing {locale}: created", dry_run)

        change("PATCH", f"/v1/appStoreVersions/{version['id']}", {
            "data": {"type": "appStoreVersions", "id": version["id"],
                     "attributes": {"copyright": app["copyright"]}}},
            f"{platform} copyright: updated", dry_run)

        status, review = client.call(
            "GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
        r = META["review"]
        attributes = {"contactFirstName": r["firstName"],
                      "contactLastName": r["lastName"], "contactEmail": r["email"],
                      "contactPhone": r["phone"],
                      "demoAccountRequired": r["demoAccountRequired"], "notes": r["notes"]}
        if status == 200 and review.get("data"):
            review_id = review["data"]["id"]
            change("PATCH", f"/v1/appStoreReviewDetails/{review_id}", {
                "data": {"type": "appStoreReviewDetails", "id": review_id,
                         "attributes": attributes}},
                f"{platform} review details: updated", dry_run)
        else:
            change("POST", "/v1/appStoreReviewDetails", {
                "data": {"type": "appStoreReviewDetails", "attributes": attributes,
                         "relationships": {"appStoreVersion": {"data": {
                             "type": "appStoreVersions", "id": version["id"]}}}}},
                f"{platform} review details: created", dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
