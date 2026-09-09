#!/usr/bin/env python3
"""Create or reuse the provisioning profile for a Mac App Store build."""

from __future__ import annotations

import argparse
import base64
import hashlib
import pathlib

import client


def certificate_bytes(item: dict) -> bytes:
    return base64.b64decode(item["attributes"]["certificateContent"])


def distribution_certificate(sha1: str) -> dict:
    wanted = sha1.replace(":", "").upper()
    certificates = client.paged(
        "/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=200"
    )
    for item in certificates:
        actual = hashlib.sha1(certificate_bytes(item)).hexdigest().upper()  # noqa: S324
        if actual == wanted:
            return item
    raise SystemExit(f"App Store Connect has no active Distribution certificate {wanted}")


def bundle_id(identifier: str) -> dict:
    items = client.paged(
        f"/v1/bundleIds?filter%5Bidentifier%5D={identifier}&limit=20"
    )
    if len(items) != 1:
        raise SystemExit(f"expected one bundle ID for {identifier}, found {len(items)}")
    return items[0]


def mac_profile(identifier: str, distribution: dict) -> dict:
    name = "CrispChess MacAppStore CI"
    profiles = client.paged("/v1/profiles?limit=200")
    for item in profiles:
        attrs = item["attributes"]
        if (attrs.get("name") == name and attrs.get("profileType") == "MAC_APP_STORE"
                and attrs.get("profileState") == "ACTIVE"):
            print("reusing Mac App Store profile", item["id"])
            return item
    item = client.expect("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "MAC_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds",
                                      "id": bundle_id(identifier)["id"]}},
            "certificates": {"data": [{"type": "certificates",
                                          "id": distribution["id"]}]},
        },
    }})["data"]
    print("created Mac App Store profile", item["id"])
    return item


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--distribution-sha1", required=True)
    parser.add_argument("--profile-out", required=True, type=pathlib.Path)
    args = parser.parse_args()
    distribution = distribution_certificate(args.distribution_sha1)
    profile = mac_profile(args.bundle_id, distribution)
    args.profile_out.write_bytes(
        base64.b64decode(profile["attributes"]["profileContent"])
    )


if __name__ == "__main__":
    main()
