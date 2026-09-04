#!/usr/bin/env bash
# Build Lynx chess engine to WebAssembly.
#
# Requires: .NET 10 SDK + wasm-tools workload
#   Install: curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
#            dotnet workload install wasm-tools
#
# Usage: ./scripts/build_lynx_wasm.sh
#
# Output: web/lynx/_framework/ (WASM bundle, ~4-6 MB)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LYNX_VERSION="wasm-browser"
LYNX_REPO="https://github.com/CrispStrobe/lynx-chess.git"
LYNX_DIR="$PROJECT_ROOT/third_party/lynx-chess"
WASM_PROJECT="$LYNX_DIR/src/Lynx.Wasm"
# Overridable so the same script can produce both bundles the app offers: the
# AOT one (default) and, with -p:RunAOTCompilation=false, the small interpreter
# one. Any extra arguments are passed straight through to `dotnet publish`.
OUTPUT_DIR="${LYNX_OUTPUT_DIR:-$PROJECT_ROOT/web/lynx}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Lynx WASM Build ===${NC}"

# 1. Check .NET SDK
if ! command -v dotnet &>/dev/null; then
  # Try common install locations
  for p in "$HOME/.dotnet/dotnet" "/usr/local/share/dotnet/dotnet"; do
    if [[ -x "$p" ]]; then
      export PATH="$(dirname "$p"):$PATH"
      export DOTNET_ROOT="$(dirname "$p")"
      break
    fi
  done
fi

if ! command -v dotnet &>/dev/null; then
  echo -e "${RED}Error: .NET SDK not found.${NC}"
  echo "Install with: curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0"
  exit 1
fi

DOTNET_VERSION=$(dotnet --version)
echo "  .NET SDK: $DOTNET_VERSION"

if ! dotnet workload list 2>/dev/null | grep -q wasm-tools; then
  echo -e "${YELLOW}Installing wasm-tools workload...${NC}"
  dotnet workload install wasm-tools
fi

# 2. Clone Lynx source if needed.
#
# An existing checkout is reused, which is how a bundle once shipped built from
# a stale tree: the directory was at upstream v1.11.0 while the branch this
# clones had moved well past it, and nothing said so. Check what is actually
# there before building it.
if [[ ! -d "$LYNX_DIR/src/Lynx" ]]; then
  echo -e "${YELLOW}Cloning Lynx (WASM fork) from ${LYNX_REPO}...${NC}"
  git clone --depth 1 --branch "$LYNX_VERSION" "$LYNX_REPO" "$LYNX_DIR"
else
  ACTUAL_REMOTE=$(git -C "$LYNX_DIR" remote get-url origin 2>/dev/null || echo "?")
  ACTUAL_REF=$(git -C "$LYNX_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  [[ "$ACTUAL_REF" == "HEAD" ]] && \
    ACTUAL_REF=$(git -C "$LYNX_DIR" describe --tags --always 2>/dev/null || echo "detached")

  if [[ "$ACTUAL_REMOTE" != "$LYNX_REPO" || "$ACTUAL_REF" != "$LYNX_VERSION" ]]; then
    echo -e "${RED}Error: $LYNX_DIR is not what this script builds from.${NC}"
    echo "  expected: $LYNX_REPO @ $LYNX_VERSION"
    echo "  found:    $ACTUAL_REMOTE @ $ACTUAL_REF"
    echo
    echo "Building it anyway would ship a bundle from source you did not choose."
    echo "Re-clone with:"
    echo "  rm -rf $LYNX_DIR && $0"
    echo "or set LYNX_ALLOW_LOCAL_CHECKOUT=1 to build the tree as it stands"
    echo "(intended for working on the engine, not for producing a release)."
    [[ "${LYNX_ALLOW_LOCAL_CHECKOUT:-}" == "1" ]] || exit 1
    echo -e "${YELLOW}LYNX_ALLOW_LOCAL_CHECKOUT=1 — building the local tree.${NC}"
  else
    echo "  Lynx source: $ACTUAL_REMOTE @ $ACTUAL_REF"
  fi
fi

# 4. Ensure Lynx.Wasm project exists
if [[ ! -f "$WASM_PROJECT/Lynx.Wasm.csproj" ]]; then
  echo -e "${RED}Error: Lynx.Wasm project not found at $WASM_PROJECT${NC}"
  echo "The Lynx.Wasm project should already exist in the cloned repo."
  exit 1
fi

# 5. Build
echo -e "${GREEN}Building Lynx WASM (AOT)...${NC}"
echo "  This may take several minutes on first build."

case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR" ;; esac

cd "$WASM_PROJECT"
dotnet publish -c Release "$@" 2>&1 | grep -E '(error|warning|Generated|Compiling|Linking|AOT|took)' || true

APPBUNDLE="$WASM_PROJECT/bin/Release/net10.0/browser-wasm/AppBundle"

if [[ ! -d "$APPBUNDLE/_framework" ]]; then
  echo -e "${RED}Build failed — no AppBundle output.${NC}"
  exit 1
fi

# 6. Copy to web/lynx/
echo -e "${GREEN}Copying WASM bundle to web/lynx/...${NC}"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp -r "$APPBUNDLE/_framework" "$OUTPUT_DIR/"

# Remove source maps. Keep *.symbols: the boot config lists it, and a .NET 10
# bundle fails to start outright when it is missing (older ones only warned).
rm -f "$OUTPUT_DIR/_framework/"*.map

BUNDLE_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
FILE_COUNT=$(find "$OUTPUT_DIR" -type f | wc -l)

echo -e "${GREEN}=== Done ===${NC}"
echo "  Output: $OUTPUT_DIR"
echo "  Size:   $BUNDLE_SIZE ($FILE_COUNT files)"
echo "  Files:"
find "$OUTPUT_DIR/_framework" -name "*.wasm" -o -name "*.js" | sort | while read f; do
  SIZE=$(du -h "$f" | cut -f1)
  echo "    $(basename "$f"): $SIZE"
done
