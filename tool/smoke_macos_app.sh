#!/usr/bin/env bash
# Run only a development/ad-hoc signed copy; keep the distribution package intact.
set -euo pipefail
app=${1:?usage: smoke_macos_app.sh CrispChess.app output-directory}
output=${2:?supply an output directory}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$output"
python3 "$root/tools/verify_macos_app.py" "$app"
app_pid=''
trap 'if [ -n "$app_pid" ]; then kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi' EXIT
for language in en de; do
  case "$language" in en) locale=en_US ;; de) locale=de_DE ;; esac
  destination="$output/$language"
  mkdir -p "$destination"
  "$app/Contents/MacOS/CrispChess" -AppleLanguages "($language)" -AppleLocale "$locale" > "$destination/app.log" 2>&1 &
  app_pid=$!
  for attempt in $(seq 1 60); do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      cat "$destination/app.log"
      echo '::error::CrispChess exited during launch'
      exit 1
    fi
    if python3 "$root/tools/verify_macos_smoke.py" "$destination/app.log" > "$destination/check.txt" 2>&1; then break; fi
    sleep 1
  done
  python3 "$root/tools/verify_macos_smoke.py" "$destination/app.log"
  swift "$root/tools/verify_macos_running.swift" "$app_pid" "$destination/window.txt" | tee "$destination/running-app.txt"
  window_id=$(cat "$destination/window.txt")
  screencapture -x -l "$window_id" "$destination/window.png"
  kill "$app_pid"
  wait "$app_pid" 2>/dev/null || true
  app_pid=''
done
