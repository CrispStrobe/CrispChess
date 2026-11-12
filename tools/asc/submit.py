#!/usr/bin/env python3
"""Submit (or resubmit) an editable App Store version (iOS or macOS) for App Review.

A rejected version sits in a review submission in state UNRESOLVED_ISSUES;
after the version has been fixed (build, listing, screenshots), resubmitting
that same submission is what App Store Connect's "Resubmit to App Review"
does. With no open submission, a new one is created with the version as its
item. An empty READY_FOR_REVIEW submission can be recovered by attaching
that version. Updates require localized whatsNew; submission ownership is
checked before writes. --dry-run performs the same checks and changes nothing.
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


def check_localized_whats_new(version_id: str) -> None:
    """Require localized release notes for an update (callers classify history)."""
    localizations = client.paged(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")
    if not localizations:
        raise ValueError("No version localizations found; localized whatsNew is required")
    missing = []
    for localization in localizations:
        attrs = localization.get("attributes", {})
        notes = attrs.get("whatsNew")
        if not isinstance(notes, str) or not notes.strip():
            missing.append(attrs.get("locale") or localization["id"])
    if missing:
        raise ValueError("Missing localized whatsNew for: " + ", ".join(missing))


def submission_plan(platform: str, version_id: str | None) -> tuple[dict | None, list[dict]]:
    """Inspect all active submissions before allowing any release mutations.

    Only an empty READY_FOR_REVIEW submission or a single item belonging to
    the intended version is safe to reuse. A missing target ID permits only
    the empty case, for a version that new_release has yet to create.
    """
    active = [s for s in client.paged(
        f"/v1/reviewSubmissions?filter[app]={APP}&filter[platform]={platform}&limit=20")
        if s["attributes"].get("state") in (
            "UNRESOLVED_ISSUES", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW")]
    if len(active) > 1:
        raise ValueError("Ambiguous active review submissions; refusing to alter them")
    if not active:
        return None, []
    submission = active[0]
    state = submission["attributes"]["state"]
    if state not in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW"):
        raise ValueError(f"Review submission is {state}; refusing to alter it")
    items = client.paged(
        f"/v1/reviewSubmissions/{submission['id']}/items?include=appStoreVersion&limit=20")
    if not items:
        if state != "READY_FOR_REVIEW":
            raise ValueError("Empty review submission is not READY_FOR_REVIEW")
    else:
        linked = items[0].get("relationships", {}).get("appStoreVersion", {}).get("data")
        if (len(items) != 1 or not version_id or not linked
                or linked.get("type") != "appStoreVersions" or linked.get("id") != version_id):
            raise ValueError("Review submission contains unrelated or ambiguous items")
    return submission, items


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--build", required=True,
                        help="CFBundleVersion the version must carry (a guard)")
    parser.add_argument("--platform", choices=["IOS", "MAC_OS"], default="IOS")
    args = parser.parse_args()
    platform = args.platform

    history = client.paged(f"/v1/apps/{APP}/appStoreVersions?limit=50")
    platform_versions = [v for v in history if v["attributes"].get("platform") == platform]
    versions = [v for v in platform_versions if v["attributes"].get("appStoreState") in EDITABLE]
    if len(versions) != 1:
        raise SystemExit(f"expected one editable {platform} version, found {len(versions)}")
    version = versions[0]
    name = version["attributes"].get("versionString")
    status, build = client.call("GET", f"/v1/appStoreVersions/{version['id']}/build")
    attached = ((build.get("data") or {}).get("attributes") or {}).get("version")
    if attached != args.build:
        raise SystemExit(f"{platform} {name} carries build {attached}, not {args.build}: run store.py first")
    print(f"{platform} {name} ({attached}), state {version['attributes'].get('appStoreState')}")

    try:
        # Apple requires What's New for updates only. Exempt only a sole
        # platform version in the complete paginated history. Unknown platform
        # data cannot establish a first release, so retain the update guard.
        first_release = (len(platform_versions) == 1
                         and all(v["attributes"].get("platform") for v in history))
        if not first_release:
            check_localized_whats_new(version["id"])
        submission, items = submission_plan(platform, version["id"])
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if args.dry_run:
        if submission is None:
            action = "create a submission and attach this version"
        elif not items:
            action = f"attach this version to empty submission {submission['id']} and submit"
        else:
            action = f"resubmit {submission['id']} with this version"
        print("dry run: would", action)
        return 0

    if submission:
        sub_id = submission["id"]
        # Resolve only the verified version's rejected item before resubmitting.
        for item in items:
            if item["attributes"].get("state") in ("REJECTED", "UNRESOLVED_ISSUES"):
                client.expect("PATCH", f"/v1/reviewSubmissionItems/{item['id']}", {"data": {
                    "type": "reviewSubmissionItems", "id": item["id"],
                    "attributes": {"resolved": True}}})
                print(f"marked item {item['id'][:12]}… resolved")
    else:
        sub_id = client.expect("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": platform},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]["id"]
    if not items:
        client.expect("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions",
                                             "id": version["id"]}}}}})
        print(f"attached {platform} {name} to submission {sub_id}")
    client.expect("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
        "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}})
    print(f"submitted {platform} {name} ({attached}) for App Review: {sub_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
