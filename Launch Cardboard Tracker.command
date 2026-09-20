#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
echo 'Allow Camera access when macOS asks.'
echo 'Hold each cardboard pose still, then press SPACE in the tracker window.'
echo 'Calibration: center, left, right, forward, backward, throttle idle, throttle full.'
exec ./tools/tracker.sh --camera 0
