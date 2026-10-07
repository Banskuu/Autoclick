#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"

echo "== Bubbles Apple Silicon packager =="
echo "Host: $(sw_vers -productVersion) / $(uname -m)"

if [ "$(uname -m)" != "arm64" ]; then
  echo "ERROR: This packaging job must run on Apple Silicon (arm64)." >&2
  exit 2
fi

swift --version
swift test
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/BubblesAutoclicker"
test -x "$BIN"

OUT="$ROOT/dist"
APP="$OUT/Bubbles Autoclicker.app"
CONTENTS="$APP/Contents"

rm -rf "$OUT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/Bubbles Autoclicker"
chmod +x "$CONTENTS/MacOS/Bubbles Autoclicker"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

# Build .icns from the existing PNG.
ICON_SOURCE="$ROOT/Resources/BubblesIcon.png"
if [ -f "$ICON_SOURCE" ]; then
  ICONSET="$ROOT/.build/BubblesIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_SOURCE" \
      --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_SOURCE" \
      --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/BubblesIcon.icns"
fi

plutil -lint "$CONTENTS/Info.plist"

# Local ad-hoc signing. This is enough for private/testing builds.
# Public distribution without Gatekeeper warnings later needs Developer ID
# signing + Apple notarization.
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# ZIP preserves the .app bundle exactly.
ditto -c -k --sequesterRsrc --keepParent \
  "$APP" "$OUT/Bubbles-Autoclicker-Apple-Silicon.zip"

# Friendly DMG: drag app into Applications.
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Bubbles Autoclicker" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$OUT/Bubbles-Autoclicker-Apple-Silicon.dmg"

rm -rf "$STAGE"

echo ""
echo "Built:"
echo "  $OUT/Bubbles-Autoclicker-Apple-Silicon.dmg"
echo "  $OUT/Bubbles-Autoclicker-Apple-Silicon.zip"
