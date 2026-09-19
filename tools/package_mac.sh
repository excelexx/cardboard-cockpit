#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
engine="$project_dir/.tools/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$engine" ] || [ ! -f "$project_dir/.tools/macos.zip" ]; then
  "$project_dir/tools/setup.sh" --export
fi
output_dir="${COCKPIT_BUILD_OUTPUT:-$project_dir/build}"
mkdir -p "$output_dir"
# macOS file-provider folders can stamp FinderInfo while codesign reads a
# bundle. Sign in the OS temporary directory, then archive without metadata.
native_stage="$(mktemp -d /private/tmp/cardboard-cockpit-build.XXXXXX)"
trap 'rm -rf "$native_stage"' EXIT
release_dir="$native_stage/Cardboard Cockpit"
app_bundle="$release_dir/Cardboard Cockpit.app"
mkdir -p "$release_dir/Source"
cd "$project_dir/simulator"
"$engine" --headless --path "$project_dir/simulator" --editor --import --quit
"$engine" --headless --path "$project_dir/simulator" --export-release macOS "$app_bundle"
xattr -dr com.apple.FinderInfo "$app_bundle" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app_bundle" 2>/dev/null || true
codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
# Include source and original licensed aircraft assets with the distributable.
# Explicit paths exclude credentials, environments, downloads and local builds.
tar -C "$project_dir" --exclude='simulator/.godot' --exclude='__pycache__' --exclude='vision/calibration.local.json' --exclude='vision/recordings' -cf - simulator vision tools docs shared README.md THIRD_PARTY_ASSETS.md | tar -C "$release_dir/Source" -xf -
ditto --norsrc "$app_bundle" "$output_dir/Cardboard Cockpit.app"
ditto -c -k --norsrc --keepParent "$release_dir" "$output_dir/Cardboard Cockpit Mac.zip"
echo "Built: $output_dir/Cardboard Cockpit.app"
echo "Archive with source: $output_dir/Cardboard Cockpit Mac.zip"
echo "The build is locally signed; it is not Apple-notarized for public distribution."
