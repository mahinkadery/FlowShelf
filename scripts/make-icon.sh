#!/bin/bash
# Generate a macOS .icns from a single square PNG (ideally 1024x1024).
# Usage: scripts/make-icon.sh <source.png> <output.icns>
set -e

SRC="$1"
OUT="$2"

if [ ! -f "$SRC" ]; then
  echo "make-icon: source '$SRC' not found — skipping icon generation."
  exit 0
fi

TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

gen() { sips -z "$1" "$1" "$SRC" --out "$ICONSET/$2" >/dev/null; }

gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$TMP"
echo "make-icon: wrote $OUT"
