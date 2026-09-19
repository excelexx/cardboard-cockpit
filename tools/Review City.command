#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/.tools/Godot.app/Contents/MacOS/Godot" --path "$project_dir/simulator" --log-file "$project_dir/docs/screenshots/city-review.log" --script tests/test_city.gd -- --visual
