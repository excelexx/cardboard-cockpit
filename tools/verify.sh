#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
engine="$project_dir/.tools/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$engine" ]; then ./tools/setup.sh; fi
if [ ! -x .venv/bin/python ]; then ./tools/setup_vision.sh; fi
"$engine" --headless --path simulator --editor --import --quit
"$engine" --headless --path simulator --script res://scenes/main.gd --check-only
"$engine" --headless --path simulator --script res://tests/test_fighter.gd
"$engine" --headless --path simulator --script res://tests/test_arcade_controls.gd
"$engine" --headless --path simulator --script res://tests/test_sticker_controls.gd
"$engine" --headless --path simulator --script res://tests/test_spectre_scene.gd
"$engine" --headless --path simulator --script res://tests/test_radio.gd
"$engine" --headless --path simulator --script res://tests/test_demo_mission.gd
"$engine" --headless --path simulator --script res://tests/test_ballistics.gd
"$engine" --headless --path simulator --script res://tests/test_combat_feel.gd
"$engine" --headless --path simulator --script res://tests/test_balance_profile.gd
"$engine" --headless --path simulator --script res://tests/test_scenic_route.gd
"$engine" --headless --path simulator --script res://tests/test_city.gd
"$engine" --headless --path simulator --script res://tests/test_grounding.gd
"$engine" --headless --path simulator --script res://tests/test_urban_expansion.gd
"$engine" --headless --path simulator --fixed-fps 60 -- --combat --autotest
"$engine" --headless --path simulator --fixed-fps 60 -- --approach --autotest
.venv/bin/python -m unittest discover -s vision/tests -v
"$engine" --headless --path simulator --script ../tools/test_vision_client.gd
printf '%s\n' 'PASS: SPECTRE flight, combat, camera, landing, audio and cardboard integration.'
