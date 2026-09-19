#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
# A terminal exit or game exit must also release both cameras.
./tools/dual_camera_tracker.sh "$@" &
tracker_pid=$!
cleanup() {
  kill -TERM "$tracker_pid" 2>/dev/null || true
  wait "$tracker_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
./tools/run.sh -- --dual-cameras --paper-test
