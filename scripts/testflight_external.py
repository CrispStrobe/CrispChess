#!/usr/bin/env python3
"""Put an uploaded build in front of TestFlight's *external* testers.

Uploading only gets a build into TestFlight for internal testers. External
testing is a separate act: the build has to carry "what to test" notes, be
attached to an external group, and be submitted for Apple's Beta App Review.
This does those three things through the App Store Connect API, so a release
does not stop half-finished waiting for someone to click through the web UI.

Usage:
    testflight_external.py --app-id 123 --version 2.1.0 --build 7 \\
        --group "External Testers" [--whats-new-file CHANGELOG.md] [--dry-run]

Credentials come from the environment, the same ones the upload step uses:
    ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8   (the key's PEM text)

Exits non-zero only on a real failure. A build already submitted, or a group
that already has it, is reported and treated as success — re-running a release
should not fail because it half-succeeded last time.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def die(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def token() -> str:
    """A short-lived ES256 JWT, which is the only thing the API accepts."""
    try:
        import jwt  # PyJWT
    except ImportError:
        die("PyJWT is required: pip install pyjwt cryptography")

    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    private_key = os.environ.get("ASC_API_KEY_P8")
    if not (key_id and issuer and private_key):
        die("set ASC_KEY_ID, ASC_ISSUER_ID and ASC_API_KEY_P8")

    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(method: str, path: str, jwt_token: str, body=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {jwt_token}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} -> {e.code}\n{detail}") from None


def find_build(jwt_token: str, app_id: str, version: str, build: str, tries: int):
    """The build Apple has finished processing, or None.

    Processing takes minutes, and the build simply does not exist in the API
    until it finishes, so this polls rather than failing on the first look.
    """
    query = (
        f"/builds?filter[app]={app_id}"
        f"&filter[preReleaseVersion.version]={version}"
        f"&filter[version]={build}&limit=1"
    )
    for attempt in range(1, tries + 1):
        found = call("GET", query, jwt_token).get("data") or []
        if found:
            state = found[0]["attributes"].get("processingState")
            print(f"  build {version}({build}): {state}")
            if state == "VALID":
                return found[0]
            if state == "FAILED":
                die("Apple rejected the build during processing")
        else:
            print(f"  build {version}({build}) not visible yet "
                  f"(attempt {attempt}/{tries})")
        if attempt < tries:
            time.sleep(60)
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True, help="e.g. 2.1.0")
    parser.add_argument("--build", required=True, help="e.g. 7")
    parser.add_argument("--group", required=True, help="external group name")
    parser.add_argument("--whats-new-file")
    parser.add_argument("--wait-minutes", type=int, default=30)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    jwt_token = token()

    print(f"Waiting for {args.version}({args.build}) to finish processing…")
    build = find_build(jwt_token, args.app_id, args.version, args.build,
                       tries=max(1, args.wait_minutes))
    if not build:
        die(f"build {args.version}({args.build}) never became VALID — it may "
            f"still be processing; re-run this step once it has")
    build_id = build["id"]

    groups = call("GET", f"/apps/{args.app_id}/betaGroups?limit=200",
                  jwt_token).get("data") or []
    names = [g["attributes"]["name"] for g in groups]
    match = next((g for g in groups if g["attributes"]["name"] == args.group), None)
    if not match:
        die(f"no beta group named {args.group!r}. Groups on this app: "
            f"{', '.join(names) or '(none)'}")
    if not match["attributes"].get("isInternalGroup", False):
        print(f"  group {args.group!r}: external")
    else:
        die(f"group {args.group!r} is an internal group — internal testers get "
            f"builds automatically and need no review; name an external one")

    if args.dry_run:
        print("dry run: would set release notes, attach the build to the group "
              "and submit it for Beta App Review")
        return

    if args.whats_new_file:
        notes = open(args.whats_new_file, encoding="utf-8").read().strip()
        # Apple caps this at 4000 characters.
        notes = notes[:4000]
        localisations = call(
            "GET", f"/builds/{build_id}/betaBuildLocalizations", jwt_token
        ).get("data") or []
        for localisation in localisations:
            call("PATCH", f"/betaBuildLocalizations/{localisation['id']}", jwt_token, {
                "data": {
                    "type": "betaBuildLocalizations",
                    "id": localisation["id"],
                    "attributes": {"whatsNew": notes},
                }
            })
        print(f"  release notes set on {len(localisations)} localisation(s)")

    try:
        call("POST", "/betaGroups/%s/relationships/builds" % match["id"], jwt_token,
             {"data": [{"type": "builds", "id": build_id}]})
        print(f"  attached to {args.group!r}")
    except RuntimeError as e:
        # Already attached is a success for our purposes.
        if "already" not in str(e).lower():
            raise
        print(f"  already attached to {args.group!r}")

    try:
        call("POST", "/betaAppReviewSubmissions", jwt_token, {
            "data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        })
        print("  submitted for Beta App Review")
    except RuntimeError as e:
        if "already" in str(e).lower() or "STATE_ERROR" in str(e):
            print("  already submitted for Beta App Review")
        else:
            raise

    print(f"\n{args.version}({args.build}) is with Apple for beta review. "
          f"External testers get it once that passes.")


if __name__ == "__main__":
    main()
