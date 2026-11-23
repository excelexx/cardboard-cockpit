#!/bin/bash
# Double-click: starts the badge bridge, the cardboard tracker and the game together.
cd "$(dirname "$0")" && exec ./tools/play.sh "$@"
