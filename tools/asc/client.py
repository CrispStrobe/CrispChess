#!/usr/bin/env python3
"""Small App Store Connect API client shared by the release tools."""

from __future__ import annotations

import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
KEY_ID = os.environ.get("ASC_KEY_ID", "9RMU3C7422")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "5f618ba3-98ef-42ad-835c-fbbef6c76cf5")


def _private_key() -> bytes:
    encoded = os.environ.get("ASC_API_KEY_P8_BASE64")
    if encoded:
        return base64.b64decode(encoded)
    path = pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
    if path.exists():
        return path.read_bytes()
    raise SystemExit("ASC_API_KEY_P8_BASE64 is unset and no local App Store Connect key exists")


def token() -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    def b64url(value: bytes) -> str:
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode()

    now = int(time.time())
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 1190,
               "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode())
        for part in (header, payload)
    )
    key = serialization.load_pem_private_key(_private_key(), password=None)
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{b64url(signature)}"


def call(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", "Bearer " + token())
    if data:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, {"raw": raw.decode(errors="replace")}


def expect(method: str, path: str, body: dict | None = None,
           ok: tuple[int, ...] = (200, 201, 204)) -> dict:
    status, document = call(method, path, body)
    delays = (3, 10, 20) if method in ("GET", "PATCH", "DELETE") else ()
    for delay in delays:
        if status < 500 or status in ok:
            break
        time.sleep(delay)
        status, document = call(method, path, body)
    if status not in ok:
        print(f"{method} {path} -> HTTP {status}", file=sys.stderr)
        for error in document.get("errors", [{"detail": json.dumps(document)}]):
            print("  " + error.get("detail", ""), file=sys.stderr)
        raise SystemExit(1)
    return document


def paged(path: str) -> list[dict]:
    result: list[dict] = []
    while path:
        document = expect("GET", path)
        result.extend(document.get("data", []))
        path = document.get("links", {}).get("next", "")
    return result
