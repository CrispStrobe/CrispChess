#!/usr/bin/env bash
set -euo pipefail

output=${1:-appstore-shots}
mkdir -p "$output"

SCREENSHOT_OUTPUT="$output" \
  flutter test test/store_screenshots_generator_test.dart

python3 - "$output" <<'PY'
import json, pathlib, struct, sys

root = pathlib.Path(sys.argv[1])
rows = []
for locale in ("en-US", "de-DE"):
    # Same order as `scenes` in test/store_screenshots_generator_test.dart;
    # the upload keeps it, and the first screenshots are the ones seen.
    for scene in ("01-lens", "02-scan", "03-ghost", "04-voice",
                  "05-play", "06-analysis", "07-tools"):
        for suffix, display, pixels, expected in (
            ("iphone", "APP_IPHONE_67", "1320x2868", (1320, 2868)),
            ("ipad", "APP_IPAD_PRO_3GEN_129", "2064x2752", (2064, 2752)),
            ("mac", "APP_DESKTOP", "1440x900", (1440, 900)),
        ):
            name = f"{locale}-{scene}-{suffix}.png"
            path = root / name
            if not path.exists():
                raise SystemExit(f"missing screenshot: {name}")
            with path.open("rb") as image:
                signature = image.read(24)
            if signature[:8] != b"\x89PNG\r\n\x1a\n":
                raise SystemExit(f"not a PNG: {name}")
            actual = struct.unpack(">II", signature[16:24])
            if actual != expected:
                raise SystemExit(f"wrong dimensions for {name}: {actual}")
            rows.append({"name": name, "locale": locale,
                         "displayType": display, "pixels": pixels})
(root / "manifest.json").write_text(json.dumps(rows, indent=2) + "\n")
print(f"prepared {len(rows)} screenshots")
PY
