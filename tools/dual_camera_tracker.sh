#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -x "$project_dir/.venv/bin/python" ]; then
  "$project_dir/tools/setup_vision.sh"
fi
exec "$project_dir/.venv/bin/python" "$project_dir/vision/dual_camera.py" "$@"
