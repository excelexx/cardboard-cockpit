#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
echo 'Allow Camera access when macOS asks. Laptop: yoke and gun. Phone: throttle.'
echo 'Choose Play in the game for three-second calibration and the short control check.'
exec ./tools/dual_camera_tracker.sh "$@"
