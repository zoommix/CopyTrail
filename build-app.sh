#!/usr/bin/env bash
# Build CopyTrail as a double-clickable .app bundle.
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="CopyTrail"
APP_DIR="$APP_NAME.app"

swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Build produced no executable at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Sources/CopyTrail/Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Sources/CopyTrail/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS will at least launch it without quarantine pain.
codesign --force --sign - "$APP_DIR" >/dev/null

# Install into /Applications so SMAppService (launch at startup) has a
# stable path to register, and Launchpad / Spotlight pick it up.
INSTALL_DIR="/Applications/$APP_NAME.app"

# If a copy is running, terminate it before replacing the bundle —
# otherwise the cp below clobbers a live binary on disk.
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Stopping running $APP_NAME…"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    # Fallback if it didn't quit gracefully.
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "Built $APP_DIR and installed at $INSTALL_DIR"
