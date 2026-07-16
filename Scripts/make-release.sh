#!/usr/bin/env bash
#
# make-release.sh — build the app bundle and zip it for a GitHub Release.
# Uses `ditto` (not `zip`) so the bundle structure and code signature survive.
# Output: build/Tiefstand-<version>.zip + its SHA-256.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/make-app.sh"

APP="$ROOT/build/Tiefstand.app"
VERSION="$(/usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 0.1.0)"
ZIP="$ROOT/build/Tiefstand-$VERSION.zip"

echo "▸ Zipping (signature-preserving)…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ $ZIP"
/usr/bin/shasum -a 256 "$ZIP"
