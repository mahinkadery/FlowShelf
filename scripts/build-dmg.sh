#!/bin/bash
# Build a styled, compressed .dmg: app on the left, Applications on the right,
# background image with an arrow. Falls back to a plain (but working) DMG if
# Finder automation isn't permitted.
# Usage: scripts/build-dmg.sh <App.app> <output.dmg>
set -e

APP="$1"
DMG="$2"
VOL="FlowShelf"
BG_SRC="Resources/dmg-background.png"

if [ ! -d "$APP" ]; then echo "build-dmg: '$APP' not found"; exit 1; fi

# Make sure the background exists (generate it if missing).
if [ ! -f "$BG_SRC" ]; then
  swift scripts/make-dmg-bg.swift "$BG_SRC" || true
fi

STAGE="$(mktemp -d)/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [ -f "$BG_SRC" ]; then mkdir -p "$STAGE/.background"; cp "$BG_SRC" "$STAGE/.background/bg.png"; fi

# Read-write image we can decorate, sized with headroom.
RW="$(mktemp -d)/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
  -format UDRW -ov "$RW" >/dev/null

DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | egrep '^/dev/' | sed 1q | awk '{print $1}')"
MOUNT="/Volumes/$VOL"

# Best-effort Finder styling (needs automation permission; ignore failure).
osascript <<EOF 2>/dev/null || echo "build-dmg: styling skipped (Finder automation not permitted)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    try
      set background picture of opts to file ".background:bg.png"
    end try
    set position of item "FlowShelf.app" of container window to {160, 205}
    set position of item "Applications" of container window to {440, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")" "$(dirname "$RW")"
echo "build-dmg: wrote $DMG"
