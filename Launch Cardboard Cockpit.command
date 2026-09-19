#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$project_dir/.tools/Godot.app/Contents/MacOS/Godot" ]; then
  exec "$project_dir/tools/run.sh"
elif [ -d "$project_dir/build/Cardboard Cockpit.app" ]; then
  open "$project_dir/build/Cardboard Cockpit.app"
else
  exec "$project_dir/tools/run.sh"
fi
