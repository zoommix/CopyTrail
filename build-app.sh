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

# Ad-hoc sign so macOS will at least launch it without quarantine pain.
codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR — double-click it or run: open $APP_DIR"
