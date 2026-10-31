#!/usr/bin/env bash
# Removes everything install.sh created.
set -euo pipefail

APP_ID="karakol-dam"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

rm -rf "$DATA_HOME/$APP_ID"
rm -f "$HOME/.local/bin/$APP_ID"
rm -f "$DATA_HOME/applications/$APP_ID.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
echo "Blackout at Karakol Dam has been removed."
