#!/bin/bash
# Erzeugt Resources/AppIcon.icns aus tools/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build Resources
echo "==> Zeichne Icon …"
swift tools/make_icon.swift build/icon_1024.png

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

gen() { sips -z "$1" "$1" build/icon_1024.png --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp build/icon_1024.png "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "==> Resources/AppIcon.icns erstellt."
