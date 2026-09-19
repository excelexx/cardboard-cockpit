#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/.tools/Godot.app/Contents/MacOS/Godot" --path "$project_dir/simulator" --script tests/test_scenic_route.gd -- --visual
