#!/bin/bash
# Build a styled, compressed .dmg: app on the left, Applications on the right,
# background image with an arrow. Styling is required; fail instead of silently
# publishing a plain Finder window.
# Usage: scripts/build-dmg.sh <App.app> <output.dmg>
set -e

APP="$1"
DMG="$2"
VOL="FlowShelf"
BUILD_VOL="FlowShelfBuild-$$"
BG_SRC="Resources/dmg-background.jpg"

if [ ! -d "$APP" ]; then echo "build-dmg: '$APP' not found"; exit 1; fi

# (Re)generate the composed background so base/logo changes are picked up.
swift scripts/make-dmg-bg.swift "$BG_SRC" || true

STAGE_ROOT="$(mktemp -d)"
RW_ROOT="$(mktemp -d)"
STAGE="$STAGE_ROOT/stage"
RW="$RW_ROOT/rw.dmg"
DEV=""

cleanup() {
  if [ -n "$DEV" ]; then
    hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE_ROOT" "$RW_ROOT"
}
trap cleanup EXIT

mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
if [ -f "$BG_SRC" ]; then mkdir -p "$STAGE/.background"; cp "$BG_SRC" "$STAGE/.background/bg.jpg"; fi

# Read-write image we can decorate, sized with headroom.
hdiutil create -srcfolder "$STAGE" -volname "$BUILD_VOL" -fs HFS+ \
  -format UDRW -ov "$RW" >/dev/null

ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
VOLUME_LINE="$(printf '%s\n' "$ATTACH" | awk '$NF ~ /^\/Volumes\// {print; exit}')"
DEV="$(printf '%s\n' "$VOLUME_LINE" | awk '{print $1}')"
MOUNT="$(printf '%s\n' "$VOLUME_LINE" | awk '{print $NF}')"
[ -n "$DEV" ] && [ -d "$MOUNT" ] || { echo "build-dmg: failed to locate mounted build volume"; exit 1; }

# The temporary volume name is unique, so Finder can never style an older
# FlowShelf DMG that the user happens to have mounted.
osascript <<EOF
tell application "Finder"
  tell disk "$BUILD_VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {220, 140, 880, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 12
    try
      set background picture of opts to file ".background:bg.jpg"
    end try
    set position of item "FlowShelf.app" of container window to {190, 200}
    set position of item "Applications" of container window to {470, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
for _ in {1..20}; do
  [ -f "$MOUNT/.DS_Store" ] && break
  sleep 0.25
done
[ -f "$MOUNT/.DS_Store" ] || { echo "build-dmg: Finder styling failed (.DS_Store missing)"; exit 1; }

# Rename only after Finder writes the layout. This preserves the final public
# volume name while keeping the styling target unambiguous during the build.
diskutil renameVolume "$DEV" "$VOL" >/dev/null
sync
hdiutil detach "$DEV" >/dev/null
DEV=""

rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
echo "build-dmg: wrote $DMG"
