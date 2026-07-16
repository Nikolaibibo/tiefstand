#!/usr/bin/env bash
#
# make-icon.sh — regenerate the app icon from Scripts/make-icon.swift.
# Renders a 1024px PNG, builds a full .iconset, and compiles icon/Tiefstand.icns
# (committed; make-app.sh copies it into the bundle). Run when the icon changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
ICONSET="$BUILD/Tiefstand.iconset"
SRC="$BUILD/icon-1024.png"

mkdir -p "$BUILD" "$ROOT/icon"
echo "▸ Rendering 1024px icon…"
swift Scripts/make-icon.swift "$SRC"

echo "▸ Building iconset…"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  d=$((s * 2))
  sips -z $s $s "$SRC" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
  sips -z $d $d "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"   # 1024 = 512@2x

echo "▸ Compiling icns…"
iconutil -c icns "$ICONSET" -o "$ROOT/icon/Tiefstand.icns"
echo "✓ icon/Tiefstand.icns"
