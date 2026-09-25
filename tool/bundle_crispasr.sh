#!/usr/bin/env bash
# Copies CrispASR's prebuilt library into a built desktop app, for voice moves.
#
#   tool/bundle_crispasr.sh linux   build/linux/x64/release/bundle
#   tool/bundle_crispasr.sh macos   build/macos/Build/Products/Release/CrispChess.app
#   tool/bundle_crispasr.sh windows build/windows/x64/runner/Release
#
# CRISPASR_VERSION names the CrispASR release (e.g. v0.8.37). The app finds
# the library by name next to itself (Linux: bundle/lib, which Flutter's
# rpath covers, and libcrispasr's own $ORIGIN runpath finds the ggml
# libraries beside it; macOS: Contents/Frameworks; Windows: next to the exe),
# and hides the microphone when the library is missing or predates phrase
# scoring — so a release without it still ships a working app.
set -euo pipefail

platform=$1
target=$2
version=${CRISPASR_VERSION:?set CRISPASR_VERSION to a CrispASR release tag}
case $platform in
  linux) asset=libcrispasr-linux-x86_64 ;;
  macos) asset=libcrispasr-macos-arm64 ;;
  windows) asset=libcrispasr-windows-x86_64 ;;
  *) echo "unknown platform $platform" >&2; exit 2 ;;
esac

work=${RUNNER_TEMP:-$(mktemp -d)}
curl -sSLf --retry 3 -o "$work/$asset.tar.gz" \
  "https://github.com/CrispStrobe/CrispASR/releases/download/$version/$asset.tar.gz"
tar -xzf "$work/$asset.tar.gz" -C "$work"
src=$work/$asset

case $platform in
  linux)
    cp -P "$src"/lib/*.so* "$target/lib/"
    lib=$target/lib/libcrispasr.so
    symbols=$(nm -D "$lib")
    ;;
  macos)
    frameworks=$target/Contents/Frameworks
    mkdir -p "$frameworks"
    cp -P "$src"/lib/*.dylib "$frameworks/"
    # Changing Contents invalidates the app's signature: sign the new
    # libraries, then the app again (ad hoc, keeping its entitlements).
    find "$frameworks" -maxdepth 1 -name '*.dylib' -type f -exec codesign --force --sign - {} \;
    codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$target"
    codesign --verify --deep --strict "$target"
    lib=$frameworks/libcrispasr.dylib
    symbols=$(nm -gU "$lib")
    ;;
  windows)
    cp "$src"/bin/crispasr.dll "$src"/bin/ggml*.dll "$target/"
    lib=$target/crispasr.dll
    # No nm on the Windows runner by default; the app checks at run time.
    symbols=$(strings "$lib" 2>/dev/null || true)
    ;;
esac

ls -la "$lib"
if grep -q crispasr_session_score_texts <<<"$symbols"; then
  echo "CrispASR $version bundled: voice moves enabled"
else
  echo "::warning::CrispASR $version predates phrase scoring: the app will hide voice moves"
fi
