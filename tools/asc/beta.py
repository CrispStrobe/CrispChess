#!/usr/bin/env python3
"""Keep TestFlight copy bilingual and report the current review state."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import client  # noqa: E402

META = json.loads((pathlib.Path(__file__).resolve().parent / "metadata.json").read_text())
APP = META["appId"]
LOCALES = {META["primaryLocale"]: {"app": META["app"], "beta": META["beta"]},
           **META.get("locales", {})}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="12")
    args = parser.parse_args()
    builds = [build for build in client.paged(f"/v1/apps/{APP}/builds?limit=200")
              if build["attributes"].get("version") == args.build and
              build["attributes"].get("processingState") == "VALID"]
    if len(builds) != 1:
        raise SystemExit(f"expected one valid build {args.build}, found {len(builds)}")
    build_id = builds[0]["id"]

    existing = {loc["attributes"]["locale"]: loc for loc in client.paged(
        f"/v1/apps/{APP}/betaAppLocalizations?limit=50")}
    for locale, copy in LOCALES.items():
        attributes = {"description": copy["beta"]["description"],
                      "feedbackEmail": META["beta"]["feedbackEmail"],
                      "privacyPolicyUrl": copy["app"].get(
                          "privacyPolicyUrl", META["app"]["privacyPolicyUrl"])}
        if locale in existing:
            loc_id = existing[locale]["id"]
            client.expect("PATCH", f"/v1/betaAppLocalizations/{loc_id}", {
                "data": {"type": "betaAppLocalizations", "id": loc_id,
                         "attributes": attributes}})
            print(f"beta listing {locale}: updated")
        else:
            client.expect("POST", "/v1/betaAppLocalizations", {"data": {
                "type": "betaAppLocalizations",
                "attributes": {**attributes, "locale": locale},
                "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
            print(f"beta listing {locale}: created")

    existing = {loc["attributes"]["locale"]: loc for loc in client.paged(
        f"/v1/builds/{build_id}/betaBuildLocalizations?limit=50")}
    for locale, copy in LOCALES.items():
        attributes = {"whatsNew": copy["beta"]["whatToTest"]}
        if locale in existing:
            loc_id = existing[locale]["id"]
            client.expect("PATCH", f"/v1/betaBuildLocalizations/{loc_id}", {
                "data": {"type": "betaBuildLocalizations", "id": loc_id,
                         "attributes": attributes}})
            print(f"what to test {locale}: updated")
        else:
            client.expect("POST", "/v1/betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations",
                "attributes": {**attributes, "locale": locale},
                "relationships": {"build": {"data": {"type": "builds",
                                                        "id": build_id}}}}})
            print(f"what to test {locale}: created")

    submissions = client.paged(
        f"/v1/betaAppReviewSubmissions?filter[build]={build_id}&limit=10")
    state = submissions[0]["attributes"].get("betaReviewState") if submissions else "NOT_SUBMITTED"
    print(f"build {args.build} beta review: {state}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
