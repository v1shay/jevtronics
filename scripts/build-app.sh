#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/outputs/Jev Notch.app"
CONTENTS="$APP_DIR/Contents"

cd "$ROOT_DIR"
mkdir -p ".build/release"
xcrun swiftc -O \
  -module-cache-path "/tmp/jev-notch-swift-cache" \
  Sources/JevNotch/**/*.swift \
  -o ".build/release/JevNotch" \
  -framework AppKit \
  -framework Speech \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Contacts \
  -framework EventKit \
  -framework Security \
  -framework Network \
  -Xlinker -sectcreate \
  -Xlinker __TEXT \
  -Xlinker __info_plist \
  -Xlinker "Config/Info.plist"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/JevNotch" "$CONTENTS/MacOS/JevNotch"
cp "Config/Info.plist" "$CONTENTS/Info.plist"

codesign --force --deep --sign - --entitlements "Config/JevNotch.entitlements" "$APP_DIR"
echo "$APP_DIR"
