#!/usr/bin/env bash
# Installs "Blackout at Karakol Dam" for the current user (no sudo needed).
#   - game files  -> ~/.local/share/karakol-dam
#   - launcher    -> ~/.local/bin/karakol-dam      (run it from a terminal)
#   - menu entry  -> ~/.local/share/applications/karakol-dam.desktop
set -euo pipefail

APP_ID="karakol-dam"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST="$DATA_HOME/$APP_ID"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$DATA_HOME/applications"

if [ "$(uname -m)" != "x86_64" ]; then
  echo "This build is for 64-bit Intel/AMD (x86_64) Linux only. Your machine is $(uname -m)." >&2
  exit 1
fi

mkdir -p "$DEST" "$BIN_DIR" "$APPS_DIR"
install -m 755 "$HERE/KarakolDam.x86_64" "$DEST/KarakolDam.x86_64"
install -m 644 "$HERE/icon.svg" "$DEST/icon.svg"

cat > "$BIN_DIR/$APP_ID" <<EOF
#!/usr/bin/env bash
exec "$DEST/KarakolDam.x86_64" "\$@"
EOF
chmod 755 "$BIN_DIR/$APP_ID"

cat > "$APPS_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Blackout at Karakol Dam
Comment=Tactical stealth shooter: infiltrate the dam, sabotage it, get out
Exec=$DEST/KarakolDam.x86_64
Icon=$DEST/icon.svg
Terminal=false
Categories=Game;ActionGame;
EOF
chmod 644 "$APPS_DIR/$APP_ID.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

echo
echo "Installed."
echo "  Start it from your applications menu: \"Blackout at Karakol Dam\""
echo "  or from a terminal:                    $APP_ID"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "  (note: $BIN_DIR is not in your PATH; use $DEST/KarakolDam.x86_64 instead)";;
esac
echo "  To remove it later: ./uninstall.sh"
