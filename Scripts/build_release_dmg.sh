#!/bin/zsh
set -euo pipefail

VERSION="${1:-1.2.12}"
ROOT_DIRECTORY="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT_DIRECTORY="$ROOT_DIRECTORY/Artifacts"
APP_DIRECTORY="$ARTIFACT_DIRECTORY/BitFi.app"
APP_CONTENTS="$APP_DIRECTORY/Contents"
OUTPUT_PATH="$ARTIFACT_DIRECTORY/BitFi-${VERSION}-universal.dmg"

mkdir -p "$ARTIFACT_DIRECTORY"
rm -rf "$APP_DIRECTORY"

cd "$ROOT_DIRECTORY"
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0

mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources"
lipo -create \
  "$ROOT_DIRECTORY/.build/arm64-apple-macosx/release/BitFi" \
  "$ROOT_DIRECTORY/.build/x86_64-apple-macosx/release/BitFi" \
  -output "$APP_CONTENTS/MacOS/BitFi"

cp "$ROOT_DIRECTORY/BitFi/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIRECTORY/BitFi/Resources/BitFi.icns" "$APP_CONTENTS/Resources/BitFi.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable BitFi" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.ninnja.BitFi" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_DIRECTORY"

"$ROOT_DIRECTORY/Scripts/create_dmg.sh" \
  "$APP_DIRECTORY" \
  "$ROOT_DIRECTORY/Packaging/BitFi-DMG-background.png" \
  "$OUTPUT_PATH"

print "Release artifact: $OUTPUT_PATH"
