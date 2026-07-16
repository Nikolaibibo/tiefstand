#!/usr/bin/env bash
#
# make-app.sh — assemble a real macOS .app bundle from the SwiftPM executable.
#
# Tiefstand is a menu-bar (agent) app: SwiftUI's MenuBarExtra needs a proper
# .app bundle with an Info.plist that sets LSUIElement, so the process runs as
# a background agent with a status item and no Dock icon. `swift build` alone
# only produces a bare Mach-O executable, which macOS won't treat as an app.
#
# This script keeps SwiftPM as the single source of truth (no .xcodeproj) and
# wraps the release binary into build/Tiefstand.app, ad-hoc code-signed so it
# launches on the build machine without a paid Apple Developer account.
#
# Usage:  Scripts/make-app.sh [--run]
#   --run   launch the bundle after building
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Tiefstand"
BUNDLE_ID="com.nikolaibockholt.Tiefstand"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="13.0"

CONFIG="release"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Building $APP_NAME ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN="$(swift build -c "$CONFIG" --product "$APP_NAME" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "✗ Executable not found at $BIN" >&2
  exit 1
fi

echo "▸ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Nikolai Bockholt. MIT-licensed. Water data © NIWIS/BfG and WSV/PEGELONLINE.</string>
    <key>NSLocationUsageDescription</key><string>Tiefstand uses your location to find the nearest water gauge.</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code-signing…"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "--run" ]]; then
  echo "▸ Launching…"
  # kill a previous instance so MenuBarExtra re-registers cleanly
  pkill -x "$APP_NAME" 2>/dev/null || true
  open "$APP"
fi
