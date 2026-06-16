#!/bin/bash
# Build a compressed .dmg containing the app and an /Applications shortcut.
# Usage: scripts/build-dmg.sh <App.app> <output.dmg>
set -e

APP="$1"
DMG="$2"

if [ ! -d "$APP" ]; then echo "build-dmg: '$APP' not found"; exit 1; fi

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"      # drag-to-install UX

rm -f "$DMG"
hdiutil create -volname "FlowShelf" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "build-dmg: wrote $DMG"
