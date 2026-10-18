#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_dir="$project_dir/Transfer Hub.app"

cd "$project_dir"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/TransferHub" "$app_dir/Contents/MacOS/TransferHub"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
iconset_dir="$project_dir/.build/AppIcon.iconset"
master_icon="$project_dir/.build/AppIcon-1024.png"
mkdir -p "$iconset_dir"
swift "$project_dir/scripts/generate-app-icon.swift" "$master_icon"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$master_icon" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$master_icon" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
mtp_helper="/Applications/OpenMTP.app/Contents/Resources/bin/mtp-cli"
if [ -x "$mtp_helper" ]; then
  cp "$mtp_helper" "$app_dir/Contents/Helpers/mtp-cli"
  chmod +x "$app_dir/Contents/Helpers/mtp-cli"
fi
codesign --force --deep --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
