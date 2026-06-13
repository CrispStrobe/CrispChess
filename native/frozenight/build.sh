#!/bin/bash
set -e

echo "Building Frozenight FFI library..."
cd "$(dirname "$0")"

# Detect platform and build
case "$(uname -s)" in
  Linux)
    echo "Building for Linux..."
    cargo build --release
    cp target/release/libfrozenight_ffi.so ../../linux/
    echo "Built: linux/libfrozenight_ffi.so"
    ;;
  Darwin)
    echo "Building for macOS..."
    cargo build --release
    cp target/release/libfrozenight_ffi.dylib ../../macos/
    echo "Built: macos/libfrozenight_ffi.dylib"

    # Cross-compile for iOS if targets available
    if rustup target list --installed | grep -q aarch64-apple-ios; then
      echo "Building for iOS (arm64)..."
      cargo build --release --target aarch64-apple-ios
      cp target/aarch64-apple-ios/release/libfrozenight_ffi.a ../../ios/
      echo "Built: ios/libfrozenight_ffi.a"
    fi
    ;;
  *)
    echo "Building for current platform..."
    cargo build --release
    ;;
esac

echo "Done."
