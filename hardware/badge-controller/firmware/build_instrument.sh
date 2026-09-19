#!/bin/bash
# Build only. Never uploads, erases flash, or opens a serial device.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$project_dir"
cli="${ARDUINO_CLI:-$project_dir/.tools/arduino/arduino-cli}"
if [ ! -x "$cli" ]; then cli=arduino-cli; fi
extra=()
if [ -x "$project_dir/.tools/arduino/ctags-source/ctags" ]; then
  extra+=(--build-property "runtime.tools.ctags.path=$project_dir/.tools/arduino/ctags-source")
fi
"$cli" compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc "${extra[@]}" --build-path "$project_dir/build/badge-instrument" hardware/badge-controller/firmware/badge_controller
