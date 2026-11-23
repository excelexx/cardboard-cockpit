#!/bin/bash
# One command for the whole cockpit: badge bridge (Bluetooth), cardboard tracker
# (webcam) and the game. Everything stops when the game window closes.
#
#   ./tools/play.sh                 badge + tracker (camera 0) + game
#   ./tools/play.sh --camera 1      use another webcam
#   ./tools/play.sh --calibrate     redo the seven-pose yoke calibration first
#   ./tools/play.sh --no-tracker    keyboard / mouse flying, badge still on
#   ./tools/play.sh --no-badge      no Bluetooth
#   ./tools/play.sh --demo          any other flag is passed to the game
set -uo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
camera=0; tracker=1; badge=1; calibrate=0; game_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --camera) camera="$2"; shift 2 ;;
    --camera=*) camera="${1#*=}"; shift ;;
    --no-tracker) tracker=0; shift ;;
    --no-badge) badge=0; shift ;;
    --calibrate) calibrate=1; shift ;;
    *) game_args+=("$1"); shift ;;
  esac
done
[ -x .tools/Godot.app/Contents/MacOS/Godot ] || ./tools/setup.sh
if [ "$tracker" = 1 ] || [ "$badge" = 1 ]; then
  [ -x .venv/bin/python ] || ./tools/setup_vision.sh
  .venv/bin/python -c "import bleak" 2>/dev/null || .venv/bin/python -m pip install -q -r hardware/badge-controller/host/requirements.txt
fi
mkdir -p build/logs
pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
  wait 2>/dev/null
}
trap cleanup EXIT INT TERM

if [ "$badge" = 1 ]; then
  if pgrep -f "badge_bridge.py|BadgeBridge" >/dev/null; then
    echo "Badge bridge already running; using it."
  else
    .venv/bin/python hardware/badge-controller/host/badge_bridge.py > build/logs/badge.log 2>&1 &
    pids+=("$!")
    echo "Badge bridge started (log: build/logs/badge.log). First time: allow Bluetooth for Terminal when macOS asks."
  fi
fi

if [ "$tracker" = 1 ]; then
  tracker_args=(--camera "$camera" --no-preview)
  if [ "$calibrate" = 1 ] || [ ! -f vision/calibration.local.json ]; then
    tracker_args=(--camera "$camera" --calibrate)
    echo "No yoke calibration yet: the tracker window will ask for seven poses. Hold each still and press SPACE."
  fi
  .venv/bin/python vision/tracker.py "${tracker_args[@]}" > build/logs/tracker.log 2>&1 &
  pids+=("$!")
  echo "Cardboard tracker started on camera $camera (log: build/logs/tracker.log). Allow Camera access when macOS asks."
  game_args+=("--tracking")
fi

echo "Starting Wild Goose Chase. Close the game window to stop everything."
.tools/Godot.app/Contents/MacOS/Godot --path simulator "${game_args[@]}"
