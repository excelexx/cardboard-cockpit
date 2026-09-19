#!/bin/bash
# Complete deterministic software verification. Never opens a camera.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
engine="$project_dir/.tools/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$engine" ]; then
  ./tools/setup.sh
fi
if [ ! -x .venv/bin/python ]; then
  ./tools/setup_vision.sh
fi
"$engine" --headless --path simulator --editor --import --quit
"$engine" --headless --path simulator --script res://tests/test_flight.gd
"$engine" --headless --path simulator --script res://tests/test_interactions.gd
for aircraft in 0 1 2 3 4; do
  "$engine" --headless --path simulator --fixed-fps 60 -- --plane="$aircraft" --autotest
  "$engine" --headless --path simulator --fixed-fps 60 --script res://tests/test_keyboard_mission.gd -- --mission-plane="$aircraft"
done
.venv/bin/python -m unittest discover -s vision/tests -v
"$engine" --headless --path simulator --script ../tools/test_vision_client.gd
echo "PASS: flight, interactions, five copilot missions, five keyboard missions, tracker, and native connection."
