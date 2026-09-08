#!/usr/bin/env bash
set -euo pipefail

output=${1:-appstore-shots}
mkdir -p "$output"

select_device() {
  local pattern=$1
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys
pattern = re.compile(sys.argv[1], re.I)
document = json.load(sys.stdin)
matches = [device for devices in document["devices"].values() for device in devices
           if device.get("isAvailable") and pattern.search(device["name"])]
if not matches:
    raise SystemExit("no matching simulator: " + sys.argv[1])
print(matches[0]["udid"])
' "$pattern"
}

capture_device() {
  local device=$1
  local suffix=$2
  local width=$3
  local height=$4

  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b
  xcrun simctl status_bar "$device" override \
    --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 2>/dev/null || true

  xcrun simctl uninstall "$device" com.crispstrobe.crispchess 2>/dev/null || true
  SCREENSHOT_OUTPUT="$output" SCREENSHOT_SUFFIX="$suffix" \
    flutter drive \
      --driver=test_driver/store_screenshots_driver.dart \
      --target=integration_test/store_screenshots_test.dart \
      -d "$device"
  for path in "$output"/*-"$suffix".png; do
    actual=$(sips -g pixelWidth -g pixelHeight "$path" | awk '/pixel/{printf "%s ", $2}')
    if [[ "$actual" != "$width $height " ]]; then
      sips -z "$height" "$width" "$path" >/dev/null
    fi
  done
  xcrun simctl shutdown "$device" 2>/dev/null || true
}

iphone=$(select_device 'iPhone (17|16|15) Pro Max')
ipad=$(select_device 'iPad Pro.*13-inch')
capture_device "$iphone" iphone 1320 2868
capture_device "$ipad" ipad 2064 2752

python3 - "$output" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = []
for locale in ("en-US", "de-DE"):
    for scene in ("01-play", "02-analysis", "03-tools"):
        for suffix, display, pixels in (
            ("iphone", "APP_IPHONE_67", "1320x2868"),
            ("ipad", "APP_IPAD_PRO_3GEN_129", "2064x2752"),
        ):
            name = f"{locale}-{scene}-{suffix}.png"
            if not (root / name).exists():
                raise SystemExit(f"missing screenshot: {name}")
            rows.append({"name": name, "locale": locale,
                         "displayType": display, "pixels": pixels})
(root / "manifest.json").write_text(json.dumps(rows, indent=2) + "\n")
print(f"prepared {len(rows)} screenshots")
PY
