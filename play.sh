#!/usr/bin/env bash
# Run the game straight from this folder, without installing.
# If the game fails to start on an old graphics driver, try:  ./play.sh --rendering-driver opengl3
# If there is still no picture, force software rendering:     LIBGL_ALWAYS_SOFTWARE=1 ./play.sh
cd "$(dirname "${BASH_SOURCE[0]}")"
exec ./KarakolDam.x86_64 "$@"
