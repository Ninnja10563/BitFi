#!/bin/zsh
set -euo pipefail

if (( $# != 3 )); then
  print -u2 "usage: $0 <BitFi.app> <background.png> <output.dmg>"
  exit 64
fi

APP_PATH="$1"
BACKGROUND_PATH="$2"
OUTPUT_PATH="$3"

if [[ ! -d "$APP_PATH" || ! -f "$BACKGROUND_PATH" ]]; then
  print -u2 "Missing app bundle or DMG background."
  exit 66
fi

WORK_DIRECTORY="$(mktemp -d)"
RAW_DMG="$WORK_DIRECTORY/BitFi-rw.dmg"
MOUNT_POINT=""
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

hdiutil create -size 64m -fs HFS+ -volname "BitFi" -type UDIF -ov "$RAW_DMG" >/dev/null
ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RAW_DMG")"
DEVICE="$(print -r -- "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')"
MOUNT_POINT="$(print -r -- "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $3; exit }')"

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  print -u2 "Unable to mount writable disk image."
  exit 70
fi

ditto "$APP_PATH" "$MOUNT_POINT/BitFi.app"
ln -s /Applications "$MOUNT_POINT/Applications"
mkdir -p "$MOUNT_POINT/.background"
# sips expects height then width. Finder window interior is 600 × 380 points.
sips -z 380 600 "$BACKGROUND_PATH" --out "$MOUNT_POINT/.background/BitFi-DMG-background.png" >/dev/null
SetFile -a V "$MOUNT_POINT/.background"

osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "BitFi"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 480}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 104
        set text size of options to 14
        set background picture of options to file ".background:BitFi-DMG-background.png"
        set position of item "BitFi.app" to {160, 190}
        set position of item "Applications" to {455, 190}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

OUTPUT_BASE="${OUTPUT_PATH%.dmg}"
rm -f "$OUTPUT_PATH"
hdiutil convert "$RAW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_BASE" >/dev/null
print "Created ${OUTPUT_BASE}.dmg"
