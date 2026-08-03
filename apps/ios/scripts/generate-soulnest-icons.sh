#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
master_generator="$root/scripts/generate-soulnest-master-icons.swift"
release_source="$root/Sources/Assets.xcassets/AppIcon.appiconset/1024.png"
debug_source="$root/Sources/Assets.xcassets/AppIconDebug.appiconset/1024.png"
release_watch="$root/WatchApp/Assets.xcassets/AppIcon.appiconset"
debug_watch="$root/WatchApp/Assets.xcassets/AppIconDebug.appiconset"

command -v xcrun >/dev/null 2>&1 || {
  echo "error: Xcode command-line tools are required to generate SoulNest icons" >&2
  exit 1
}

command -v sips >/dev/null 2>&1 || {
  echo "error: macOS sips is required to generate SoulNest icon variants" >&2
  exit 1
}

test -f "$master_generator" || {
  echo "error: missing SoulNest icon generator: $master_generator" >&2
  exit 1
}

# Render deterministic 1024×1024 PNG masters from the checked-in CoreGraphics
# source before deriving the platform-specific variants.
xcrun swift "$master_generator" "$release_source" "$debug_source"

for source in "$release_source" "$debug_source"; do
  test -s "$source" || {
    echo "error: icon generator did not create: $source" >&2
    exit 1
  }
done

resize_icon() {
  local source="$1"
  local destination="$2"
  local pixels="$3"
  mkdir -p "$(dirname "$destination")"
  sips --resampleHeightWidth "$pixels" "$pixels" "$source" --out "$destination" >/dev/null
}

generate_watch_set() {
  local source="$1"
  local destination="$2"

  resize_icon "$source" "$destination/watch-notification-38@2x.png" 48
  resize_icon "$source" "$destination/watch-notification-42@2x.png" 55
  resize_icon "$source" "$destination/watch-companion-29@2x.png" 58
  resize_icon "$source" "$destination/watch-companion-29@3x.png" 87
  resize_icon "$source" "$destination/watch-app-38@2x.png" 80
  resize_icon "$source" "$destination/watch-app-40@2x.png" 88
  resize_icon "$source" "$destination/watch-app-41@2x.png" 92
  resize_icon "$source" "$destination/watch-app-44@2x.png" 100
  resize_icon "$source" "$destination/watch-app-45@2x.png" 102
  resize_icon "$source" "$destination/watch-quicklook-38@2x.png" 172
  resize_icon "$source" "$destination/watch-quicklook-42@2x.png" 196
  resize_icon "$source" "$destination/watch-quicklook-44@2x.png" 216
  resize_icon "$source" "$destination/watch-quicklook-45@2x.png" 234
  cp "$source" "$destination/watch-marketing-1024.png"
}

generate_watch_set "$release_source" "$release_watch"
generate_watch_set "$debug_source" "$debug_watch"

echo "Generated SoulNest Release and Debug iOS and Apple Watch icons."
