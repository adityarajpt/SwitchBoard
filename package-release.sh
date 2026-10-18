#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_dir="$project_dir/Transfer Hub.app"
dist_dir="$project_dir/dist"

cd "$project_dir"
./build-app.sh

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
architecture=$(uname -m)
if [ "$architecture" != "arm64" ]; then
  printf 'Release packaging must run on Apple silicon (arm64); found %s.\n' "$architecture" >&2
  exit 1
fi

product="SwitchBoard-$version-macOS-arm64"
zip_path="$dist_dir/$product.zip"
dmg_path="$dist_dir/$product.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/switchboard-release.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM

mkdir -p "$dist_dir" "$staging_dir/image"
ditto "$app_dir" "$staging_dir/image/Transfer Hub.app"
ln -s /Applications "$staging_dir/image/Applications"

rm -f "$zip_path" "$dmg_path" "$dist_dir/SHA256SUMS.txt"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
hdiutil create -volname "SwitchBoard $version" -srcfolder "$staging_dir/image" -ov -format UDZO "$dmg_path"

codesign --verify --deep --strict "$app_dir"
unzip -t "$zip_path"
hdiutil verify "$dmg_path"
file "$app_dir/Contents/MacOS/TransferHub"
shasum -a 256 "$dmg_path" "$zip_path" > "$dist_dir/SHA256SUMS.txt"

printf '\nRelease artifacts:\n%s\n%s\n%s\n' "$dmg_path" "$zip_path" "$dist_dir/SHA256SUMS.txt"
cat "$dist_dir/SHA256SUMS.txt"
