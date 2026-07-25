#!/usr/bin/env bash
# Renders every Play listing canvas (html/) to PNG (out/) with Chrome headless,
# at exact device-pixel sizes. Run after `node build.js`.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
WIN="$(pwd -W 2>/dev/null || pwd)"   # Windows-style path for Chrome
mkdir -p out

# name  ->  WIDTH,HEIGHT
declare -A SIZE=(
  [icon]="512,512"
  [feature]="1024,500"
  [phone-1]="1080,1920" [phone-2]="1080,1920" [phone-3]="1080,1920"
  [phone-4]="1080,1920" [phone-5]="1080,1920"
  [tablet7-1]="1200,1920" [tablet7-2]="1200,1920"
  [tablet10-1]="1600,2560" [tablet10-2]="1600,2560"
)

for name in "${!SIZE[@]}"; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --virtual-time-budget=4500 \
    --window-size="${SIZE[$name]}" \
    --screenshot="$WIN/out/$name.png" "$WIN/html/$name.html" >/dev/null 2>&1
  echo "rendered $name (${SIZE[$name]})"
done
echo "done -> out/"
