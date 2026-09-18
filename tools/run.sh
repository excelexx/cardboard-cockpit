#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
engine="$project_dir/.tools/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$engine" ]; then
  "$project_dir/tools/setup.sh"
fi
exec "$engine" --path "$project_dir/simulator" "$@"
