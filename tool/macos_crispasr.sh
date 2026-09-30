#!/usr/bin/env bash
# Puts CrispASR's universal macOS framework into a built Mac app, for voice
# moves in the Mac App Store build (macOS only: needs ditto/nm from Xcode).
#
#   CRISPASR_VERSION=v0.8.38 tool/macos_crispasr.sh build/macos/Build/Products/Release/Runner.app
#
# The flat libcrispasr-macos-arm64 archive (tool/bundle_crispasr.sh) is Apple
# silicon only; the release xcframework's macos-arm64_x86_64 slice is
# universal, like the Flutter app. It lands in Contents/Frameworks, where
# package:crispasr opens `crispasr.framework/crispasr`. The app does not link
# it: on a macOS older than the framework's minimum, loading it fails and the
# app hides the microphone instead of refusing to start. Signing is left to
# the caller (the App Store workflow signs everything in Frameworks).
set -euo pipefail

app=$1
version=${CRISPASR_VERSION:?set CRISPASR_VERSION to a CrispASR release tag}
work=${RUNNER_TEMP:-$(mktemp -d)}/crispasr-macos
rm -rf "$work"
mkdir -p "$work"

zip="$work/crispasr.xcframework.zip"
curl -sSLf --retry 3 -o "$zip" \
  "https://github.com/CrispStrobe/CrispASR/releases/download/$version/crispasr-$version-xcframework.zip"
unzip -q "$zip" 'crispasr.xcframework/macos-arm64_x86_64/crispasr.framework/*' -d "$work"
rm -f "$zip"

src="$work/crispasr.xcframework/macos-arm64_x86_64/crispasr.framework"
dest="$app/Contents/Frameworks/crispasr.framework"
rm -rf "$dest"
mkdir -p "$app/Contents/Frameworks"
ditto "$src" "$dest" # keeps the Versions/Current symlinks a macOS framework needs
rm -rf "$dest/Headers" "$dest/Versions/A/Headers" "$dest/Modules" "$dest/Versions/A/Modules"

bin="$dest/Versions/A/crispasr"
lipo -archs "$bin"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$dest/Versions/A/Resources/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$dest/Versions/A/Resources/Info.plist" 2>/dev/null || true
symbols=$(nm -gU "$bin")
for sym in _crispasr_session_score_texts _crispasr_mic_open; do
  grep -q "$sym" <<<"$symbols" || { echo "::error::CrispASR $version macOS framework lacks ${sym#_}"; exit 1; }
done
echo "CrispASR $version macOS framework bundled: voice moves enabled"
