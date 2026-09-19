#!/bin/bash
# Render deterministic source-build screenshots; never opens the webcam.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
engine="$project_dir/.tools/Godot.app/Contents/MacOS/Godot"
mkdir -p "$project_dir/docs/screenshots/immersion"
"$engine" --path "$project_dir/simulator" -- --demo --copilot --capture="$project_dir/docs/screenshots/immersion/departure.png" --capture-at=2
"$engine" --path "$project_dir/simulator" -- --demo --copilot --capture="$project_dir/docs/screenshots/immersion/interception.png" --capture-at=38
"$engine" --path "$project_dir/simulator" -- --kind=approach --flight --capture="$project_dir/docs/screenshots/immersion/approach.png" --capture-at=2
