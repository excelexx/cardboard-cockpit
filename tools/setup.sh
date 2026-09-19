#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
tool_dir="$project_dir/.tools"
godot_version="4.7.2"
release="https://github.com/godotengine/godot-builds/releases/download/$godot_version-stable"
mkdir -p "$tool_dir"
if [ ! -x "$tool_dir/Godot.app/Contents/MacOS/Godot" ]; then
  echo "Downloading the official Godot desktop engine…"
  curl -fL --retry 2 "$release/Godot_v$godot_version-stable_macos.universal.zip" -o "$tool_dir/godot.zip"
  ditto -xk "$tool_dir/godot.zip" "$tool_dir"
fi
if [ "${1:-}" = "--export" ] && [ ! -f "$tool_dir/macos.zip" ]; then
  echo "Downloading the matching official export templates…"
  curl -fL --retry 2 "$release/Godot_v$godot_version-stable_export_templates.tpz" -o "$tool_dir/templates.tpz"
  unzip -jo "$tool_dir/templates.tpz" templates/macos.zip -d "$tool_dir"
fi
"$tool_dir/Godot.app/Contents/MacOS/Godot" --headless --path "$project_dir/simulator" --editor --import --quit
echo "Ready. Run ./tools/run.sh or ./tools/package_mac.sh."
