#!/usr/bin/env bash
# Puts CrispASR into the iOS app, for voice moves (macOS only: needs Xcode).
#
#   CRISPASR_VERSION=v0.8.37 tool/ios_crispasr.sh
#
# Takes the iOS device and simulator slices of the CrispASR release's
# xcframework (the release zip also carries macOS, tvOS and visionOS slices
# and ~150-300 MB debug symbols per slice, none of which the app wants),
# makes ios/Frameworks/crispasr.xcframework from them, and wires it into
# Runner.xcodeproj with Embed & Sign (tool/wire_ios_crispasr.rb) — the
# arrangement CrisperWeaver ships. package:crispasr then finds it as
# `crispasr.framework/crispasr`. The framework must not need a newer iOS than
# the app (App Store Connect rejects that, ITMS-90208); CrispASR's targets
# iOS 15.0 since v0.8.38, and this script checks it against the app.
set -euo pipefail

version=${CRISPASR_VERSION:?set CRISPASR_VERSION to a CrispASR release tag}
root=$(cd "$(dirname "$0")/.." && pwd)
work=${RUNNER_TEMP:-$(mktemp -d)}/crispasr-ios
rm -rf "$work"
mkdir -p "$work"

zip="$work/crispasr.xcframework.zip"
curl -sSLf --retry 3 -o "$zip" \
  "https://github.com/CrispStrobe/CrispASR/releases/download/$version/crispasr-$version-xcframework.zip"
unzip -q "$zip" \
  'crispasr.xcframework/ios-arm64/crispasr.framework/*' \
  'crispasr.xcframework/ios-arm64_x86_64-simulator/crispasr.framework/*' \
  -d "$work"
rm -f "$zip"

out="$root/ios/Frameworks/crispasr.xcframework"
rm -rf "$out"
mkdir -p "$(dirname "$out")"
xcodebuild -create-xcframework \
  -framework "$work/crispasr.xcframework/ios-arm64/crispasr.framework" \
  -framework "$work/crispasr.xcframework/ios-arm64_x86_64-simulator/crispasr.framework" \
  -output "$out"

bin="$out/ios-arm64/crispasr.framework/crispasr"
ls -la "$bin"
fw_min=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$out/ios-arm64/crispasr.framework/Info.plist")
app_min=$(grep -m1 -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' "$root/ios/Runner.xcodeproj/project.pbxproj" | awk '{print $3}')
echo "CrispASR framework needs iOS $fw_min; the app targets iOS $app_min"
if [ "$(printf '%s\n%s\n' "$fw_min" "$app_min" | sort -V | tail -1)" != "$app_min" ]; then
  echo "::error::the framework needs a newer iOS ($fw_min) than the app ($app_min): App Store Connect rejects that"
  exit 1
fi
# Capture first: under pipefail, `nm | grep -q` fails when grep exits early.
symbols=$(nm -gU "$bin")
if grep -q '_crispasr_session_score_texts' <<<"$symbols"; then
  echo "CrispASR $version for iOS: phrase scoring present"
else
  echo "::error::CrispASR $version iOS framework lacks crispasr_session_score_texts"
  exit 1
fi

ruby "$root/tool/wire_ios_crispasr.rb"
