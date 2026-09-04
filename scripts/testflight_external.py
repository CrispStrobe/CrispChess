#!/usr/bin/env python3
"""Put an uploaded build in front of TestFlight's *external* testers.

Uploading only reaches internal testers. External testing needs several things
in place first, and Apple's API tells you about them one refusal at a time, so
this does them in order and is safe to re-run:

1. Export compliance. A build whose ``usesNonExemptEncryption`` is null is
   offered to nobody, internal or external. (This app answers it in
   Info.plist, so it is normally already set; checked anyway, since a build
   uploaded another way would not have it.)
2. The Beta App Review contact — name, email, phone. Per app, starts empty,
   and cannot be derived from anything: it comes from the environment.
3. A beta app description in the app's **primary** locale. Submission fails
   with "betaAppLocalizations not found for this app" when only en-US exists
   and the app's primary locale is something else.
4. "What to test" notes on the build.
5. The build attached to an external group.
6. The submission itself.

Usage:
    testflight_external.py --app-id 123 --version 2.1.0 --build 7 \\
        --group "External Testers" [--whats-new-file CHANGELOG.md] [--dry-run]

Environment:
    ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8      the API key
    BETA_CONTACT_FIRST_NAME, BETA_CONTACT_LAST_NAME,
    BETA_CONTACT_EMAIL, BETA_CONTACT_PHONE         the review contact
    BETA_APP_DESCRIPTION                           optional; what the app is
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def die(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def token():
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
        {"iss": issuer, "iat": now, "exp": now + 15 * 60,
         "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class Api:
    def __init__(self, jwt_token):
        self.token = jwt_token

    def __call__(self, method, path, body=None):
        url = path if path.startswith("http") else f"{API}{path}"
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self.token}")
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise ApiError(e.code, f"{method} {url} -> {e.code}\n{detail}")


class ApiError(RuntimeError):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status

    @property
    def is_conflict(self):
        """Already done. For every step here that is success, not failure."""
        return self.status == 409 or "already" in str(self).lower()


def wait_for_build(api, app_id, version, build, minutes):
    """The processed build, or None. It does not exist in the API until Apple
    finishes with it, so a fresh upload is missing rather than pending."""
    query = (f"/builds?filter[app]={app_id}"
             f"&filter[preReleaseVersion.version]={version}"
             f"&filter[version]={build}&limit=1")
    for attempt in range(1, minutes + 1):
        found = api("GET", query).get("data") or []
        if found:
            state = found[0]["attributes"].get("processingState")
            print(f"  build {version}({build}): {state}")
            if state == "VALID":
                return found[0]
            if state == "FAILED":
                die("Apple rejected the build during processing")
        else:
            print(f"  not visible yet ({attempt}/{minutes})")
        if attempt < minutes:
            time.sleep(60)
    return None


def ensure_export_compliance(api, build):
    if build["attributes"].get("usesNonExemptEncryption") is None:
        api("PATCH", f"/builds/{build['id']}", {
            "data": {"type": "builds", "id": build["id"],
                     "attributes": {"usesNonExemptEncryption": False}}
        })
        print("  export compliance: set to exempt")
    else:
        print("  export compliance: already answered")


def ensure_review_contact(api, app_id):
    """The contact Apple's beta reviewer would use. Per app, starts empty."""
    contact = {
        "contactFirstName": os.environ.get("BETA_CONTACT_FIRST_NAME", ""),
        "contactLastName": os.environ.get("BETA_CONTACT_LAST_NAME", ""),
        "contactEmail": os.environ.get("BETA_CONTACT_EMAIL", ""),
        "contactPhone": os.environ.get("BETA_CONTACT_PHONE", ""),
    }
    if not all(contact.values()):
        die("the Beta App Review contact is required and cannot be guessed — "
            "set BETA_CONTACT_FIRST_NAME, BETA_CONTACT_LAST_NAME, "
            "BETA_CONTACT_EMAIL and BETA_CONTACT_PHONE")
    contact["demoAccountRequired"] = False
    contact["notes"] = os.environ.get(
        "BETA_REVIEW_NOTES",
        "No account or login required. The app works fully offline; chess "
        "engines and neural-network weights are downloaded on request.")
    # The detail resource exists per app with id == app id, so this is a PATCH.
    api("PATCH", f"/betaAppReviewDetails/{app_id}", {
        "data": {"type": "betaAppReviewDetails", "id": app_id,
                 "attributes": contact}
    })
    print(f"  review contact: {contact['contactEmail']}")


def ensure_beta_description(api, app_id, primary_locale):
    """Submission 422s when this is missing in the app's *primary* locale —
    an en-US-only description is not enough for a de-DE-first app."""
    description = os.environ.get(
        "BETA_APP_DESCRIPTION",
        "A cross-platform chess app with pluggable engines: play, analyse, "
        "solve puzzles and drills, and study openings.")
    existing = api("GET",
                   f"/apps/{app_id}/betaAppLocalizations?limit=50").get("data") or []
    by_locale = {item["attributes"]["locale"]: item for item in existing}

    for locale in {primary_locale, "en-US"}:
        if locale in by_locale:
            print(f"  beta description: {locale} already present")
            continue
        try:
            api("POST", "/betaAppLocalizations", {
                "data": {
                    "type": "betaAppLocalizations",
                    "attributes": {"locale": locale, "description": description},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app_id}}},
                }
            })
            print(f"  beta description: created for {locale}")
        except ApiError as e:
            if not e.is_conflict:
                raise
            print(f"  beta description: {locale} already present")


def set_whats_new(api, build_id, notes):
    localisations = api(
        "GET", f"/builds/{build_id}/betaBuildLocalizations").get("data") or []
    for item in localisations:
        api("PATCH", f"/betaBuildLocalizations/{item['id']}", {
            "data": {"type": "betaBuildLocalizations", "id": item["id"],
                     "attributes": {"whatsNew": notes}}
        })
    print(f"  what to test: set on {len(localisations)} localisation(s)")


def find_or_create_group(api, app_id, name):
    groups = api("GET", f"/apps/{app_id}/betaGroups?limit=200").get("data") or []
    match = next((g for g in groups if g["attributes"]["name"] == name), None)
    if match:
        if match["attributes"].get("isInternalGroup"):
            die(f"group {name!r} is internal — internal testers get builds "
                f"without review; name an external group")
        print(f"  group: {name!r} (existing)")
        return match["id"]

    print(f"  group: {name!r} not found, creating "
          f"(existing: {', '.join(g['attributes']['name'] for g in groups) or 'none'})")
    created = api("POST", "/betaGroups", {
        "data": {"type": "betaGroups",
                 "attributes": {"name": name, "isInternalGroup": False},
                 "relationships": {
                     "app": {"data": {"type": "apps", "id": app_id}}}}
    })
    print("  note: a new group has no testers — add them in App Store Connect "
          "or the build will pass review with nobody to install it")
    return created["data"]["id"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--group", required=True)
    parser.add_argument("--whats-new-file")
    parser.add_argument("--wait-minutes", type=int, default=30)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api = Api(token())

    app = api("GET", f"/apps/{args.app_id}")["data"]["attributes"]
    primary_locale = app.get("primaryLocale") or "en-US"
    print(f"{app.get('name')} ({app.get('bundleId')}), "
          f"primary locale {primary_locale}")

    print(f"Waiting for {args.version}({args.build}) to finish processing…")
    build = wait_for_build(api, args.app_id, args.version, args.build,
                           max(1, args.wait_minutes))
    if not build:
        die(f"build {args.version}({args.build}) never became VALID — it may "
            f"still be processing; re-run this once it has")

    if args.dry_run:
        print("dry run: stopping before any change")
        return

    ensure_export_compliance(api, build)
    ensure_review_contact(api, args.app_id)
    ensure_beta_description(api, args.app_id, primary_locale)

    if args.whats_new_file:
        notes = open(args.whats_new_file, encoding="utf-8").read().strip()
        set_whats_new(api, build["id"], notes[:4000])  # Apple's cap

    group_id = find_or_create_group(api, args.app_id, args.group)
    try:
        api("POST", f"/betaGroups/{group_id}/relationships/builds",
            {"data": [{"type": "builds", "id": build["id"]}]})
        print(f"  attached to {args.group!r}")
    except ApiError as e:
        if not e.is_conflict:
            raise
        print(f"  already attached to {args.group!r}")

    try:
        api("POST", "/betaAppReviewSubmissions", {
            "data": {"type": "betaAppReviewSubmissions",
                     "relationships": {
                         "build": {"data": {"type": "builds",
                                            "id": build["id"]}}}}
        })
        print("  submitted for Beta App Review")
    except ApiError as e:
        if not (e.is_conflict or "STATE_ERROR" in str(e)):
            raise
        print("  already submitted for Beta App Review")

    print(f"\n{args.version}({args.build}) is with Apple for beta review. "
          f"External testers in {args.group!r} get it once that passes.")


if __name__ == "__main__":
    main()
