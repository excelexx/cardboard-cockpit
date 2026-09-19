#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/.tools/Godot.app/Contents/MacOS/Godot" --path "$project_dir/simulator" --windowed --resolution 1280x800 --log-file "$project_dir/docs/screenshots/realism-review.log" --script tests/test_city.gd -- --visual
