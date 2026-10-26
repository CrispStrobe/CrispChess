#!/usr/bin/env bash
# Sign a desktop release with sandbox, audio, and network permissions.
# Provisioning-only identities belong to the separate App Store signing flow.
set -euo pipefail

app=${1:?usage: sign_macos_adhoc.sh path/to/CrispChess.app}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
entitlements=$(mktemp)
trap 'rm -f "$entitlements"' EXIT

python3 - "$root/macos/Runner/Release.entitlements" "$entitlements" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    entitlements = plistlib.load(source)
for key in ('com.apple.application-identifier', 'com.apple.developer.team-identifier'):
    entitlements.pop(key, None)
with open(sys.argv[2], 'wb') as target:
    plistlib.dump(entitlements, target)
PY

rm -f "$app/Contents/embedded.provisionprofile"
codesign --force --sign - --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
