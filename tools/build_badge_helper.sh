#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [ ! -x .venv/bin/python ]; then ./tools/setup_vision.sh; fi
if command -v uv >/dev/null 2>&1; then
  uv pip install --python .venv/bin/python -r hardware/badge-controller/host/requirements.txt pyinstaller
else
  .venv/bin/python -m pip install -r hardware/badge-controller/host/requirements.txt pyinstaller
fi
.venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name BadgeBridge --distpath build/helpers --workpath build/pyinstaller --specpath build hardware/badge-controller/host/badge_bridge.py
