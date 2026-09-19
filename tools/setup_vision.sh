#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
# Python 3.13+ cannot install the pinned NumPy 1.x camera stack.
if [ ! -x .venv/bin/python ]; then
  python_bin=""
  for candidate in python3.12 python3.11 python3.10 python3.9 python3 /Library/Developer/CommandLineTools/usr/bin/python3; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(not ((3, 9) <= sys.version_info[:2] <= (3, 12)))' 2>/dev/null; then
      python_bin="$candidate"
      break
    fi
  done
  if [ -n "$python_bin" ]; then
    "$python_bin" -m venv .venv
  elif command -v uv >/dev/null 2>&1; then
    uv venv --python 3.12 --seed .venv
  else
    echo "Install Python 3.9–3.12 or uv, then run ./tools/setup_vision.sh again." >&2
    exit 1
  fi
fi
if command -v uv >/dev/null 2>&1; then
  uv pip install --python .venv/bin/python -r vision/requirements.txt
else
  .venv/bin/python -m pip install -r vision/requirements.txt
fi
echo "Tracker ready. No camera was opened. Test with ./tools/tracker.sh --simulate."
