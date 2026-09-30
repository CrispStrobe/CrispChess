#!/usr/bin/env python3
"""Submit (or resubmit) an editable App Store version (iOS or macOS) for App Review.

A rejected version sits in a review submission in state UNRESOLVED_ISSUES;
after the version has been fixed (build, listing, screenshots), resubmitting
that same submission is what App Store Connect's "Resubmit to App Review"
does. With no open submission, a new one is created with the version as its
item. --dry-run reports what would be submitted and changes nothing.
"""

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
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--build", required=True,
                        help="CFBundleVersion the version must carry (a guard)")
    parser.add_argument("--platform", choices=["IOS", "MAC_OS"], default="IOS")
    args = parser.parse_args()
    platform = args.platform

    versions = [v for v in client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
                if v["attributes"].get("platform") == platform
                and v["attributes"].get("appStoreState") in EDITABLE]
    if len(versions) != 1:
        raise SystemExit(f"expected one editable {platform} version, found {len(versions)}")
    version = versions[0]
    name = version["attributes"].get("versionString")
    status, build = client.call("GET", f"/v1/appStoreVersions/{version['id']}/build")
    attached = ((build.get("data") or {}).get("attributes") or {}).get("version")
    if attached != args.build:
        raise SystemExit(f"{platform} {name} carries build {attached}, not {args.build}: run store.py first")
    print(f"{platform} {name} ({attached}), state {version['attributes'].get('appStoreState')}")

    open_subs = [s for s in client.paged(
        f"/v1/reviewSubmissions?filter[app]={APP}&filter[platform]={platform}&limit=20")
        if s["attributes"].get("state") in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW")]
    if args.dry_run:
        print("dry run: would", "resubmit " + open_subs[0]["id"] if open_subs
              else "create a submission with this version")
        return 0

    if open_subs:
        sub_id = open_subs[0]["id"]
        # A rejected submission's items stay REJECTED until marked resolved;
        # until then Apple refuses the resubmit ("Version is not ready to be
        # submitted yet"). Mark ours resolved: it now carries the fixes.
        for item in client.paged(f"/v1/reviewSubmissions/{sub_id}/items?limit=20"):
            if item["attributes"].get("state") in ("REJECTED", "UNRESOLVED_ISSUES"):
                client.expect("PATCH", f"/v1/reviewSubmissionItems/{item['id']}", {"data": {
                    "type": "reviewSubmissionItems", "id": item["id"],
                    "attributes": {"resolved": True}}})
                print(f"marked item {item['id'][:12]}… resolved")
    else:
        sub_id = client.expect("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": platform},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]["id"]
        client.expect("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions",
                                             "id": version["id"]}}}}})
        print(f"created submission {sub_id} with {platform} {name}")
    client.expect("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
        "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}})
    print(f"submitted {platform} {name} ({attached}) for App Review: {sub_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
