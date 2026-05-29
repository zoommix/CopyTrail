#!/usr/bin/env bash
# Build CopyTrail as a double-clickable .app bundle.
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="CopyTrail"
APP_DIR="$APP_NAME.app"

# Default to a universal binary (arm64 + x86_64). Pass UNIVERSAL=0 to
# fall back to a host-arch-only build (faster, smaller — useful for
# fast iteration loops during development).
ARCH_FLAGS=(--arch arm64 --arch x86_64)
if [[ "${UNIVERSAL:-1}" == "0" ]]; then
    ARCH_FLAGS=()
fi

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"

BIN_PATH="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/$APP_NAME"
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

# Copy SPM resource bundles (e.g. KeyboardShortcuts localizations).
BIN_DIR="$(dirname "$BIN_PATH")"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP_DIR/Contents/Resources/" \;

# Ad-hoc sign so macOS will at least launch it without quarantine pain.
codesign --force --sign - "$APP_DIR" >/dev/null

# Install into /Applications so SMAppService (launch at startup) has a
# stable path to register, and Launchpad / Spotlight pick it up.
INSTALL_DIR="/Applications/$APP_NAME.app"

# If a copy is running, terminate it before replacing the bundle —
# otherwise the cp below clobbers a live binary on disk.
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Stopping running ${APP_NAME}…"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    # Fallback if it didn't quit gracefully.
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "Built $APP_DIR and installed at $INSTALL_DIR"
