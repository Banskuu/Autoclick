#!/bin/bash
ROOT="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
LOG="$ROOT/build_macos.log"

pause_and_exit() {
  status="${1:-1}"
  echo ""
  echo "Build log: $LOG"
  echo ""
  if [ "$status" -eq 0 ]; then
    echo "Build finished. Press any key to close..."
  else
    echo "BUILD FAILED. The exact error is shown above."
    echo "Press any key to close..."
  fi
  IFS= read -r -n 1 _key
  echo ""
  exit "$status"
}

fail() {
  echo ""
  echo "ERROR: $1" | tee -a "$LOG"
  pause_and_exit 1
}

run_step() {
  label="$1"
  shift
  echo ""
  echo "------------------------------------------------------------" | tee -a "$LOG"
  echo "$label" | tee -a "$LOG"
  echo "------------------------------------------------------------" | tee -a "$LOG"
  "$@" 2>&1 | tee -a "$LOG"
  status=${PIPESTATUS[0]}
  [ "$status" -eq 0 ] || fail "$label failed (exit code $status)."
}

: > "$LOG"

echo "Bubbles Autoclicker macOS builder 0.2" | tee -a "$LOG"
echo "=====================================" | tee -a "$LOG"
echo "Project: $ROOT" | tee -a "$LOG"
echo "Date: $(date)" | tee -a "$LOG"

[ "$(uname -s)" = "Darwin" ] || fail "This builder must be run on macOS."

if ! command -v xcode-select >/dev/null 2>&1; then
  fail "xcode-select was not found. Install Apple's Xcode Command Line Tools."
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo ""
  echo "Apple Command Line Tools are not installed."
  echo "Opening the installer now..."
  xcode-select --install >/dev/null 2>&1 || true
  echo "Finish that installation, then run this builder again."
  pause_and_exit 1
fi

if command -v xcrun >/dev/null 2>&1; then
  SWIFT="$(xcrun --find swift 2>/dev/null)"
else
  SWIFT="$(command -v swift 2>/dev/null)"
fi

[ -n "$SWIFT" ] && [ -x "$SWIFT" ] || fail "Swift could not be found."

echo "" | tee -a "$LOG"
"$SWIFT" --version 2>&1 | tee -a "$LOG"

version_line="$("$SWIFT" --version 2>/dev/null | head -n 1)"
major="$(echo "$version_line" | sed -E 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1/')"
minor="$(echo "$version_line" | sed -E 's/.*Swift version ([0-9]+)\.([0-9]+).*/\2/')"

case "$major:$minor" in
  *[!0-9:]*|"":"") fail "Could not determine the installed Swift version." ;;
esac

if [ "$major" -lt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -lt 9 ]; }; then
  fail "Swift 5.9 or newer is required. Update Xcode / Command Line Tools."
fi

cd "$ROOT" || fail "Could not enter the project folder."

run_step "1/6  Running shared-core tests" "$SWIFT" test
run_step "2/6  Building release binary" "$SWIFT" build -c release

BIN_DIR="$("$SWIFT" build -c release --show-bin-path 2>>"$LOG")"
BIN="$BIN_DIR/BubblesAutoclicker"
[ -x "$BIN" ] || fail "Release binary was not found at: $BIN"

APP="$ROOT/dist/Bubbles Autoclicker.app"
CONTENTS="$APP/Contents"

echo ""
echo "3/6  Creating app bundle" | tee -a "$LOG"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" || fail "Could not create app bundle."
cp "$BIN" "$CONTENTS/MacOS/Bubbles Autoclicker" || fail "Could not copy app executable."
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist" || fail "Could not copy Info.plist."
chmod +x "$CONTENTS/MacOS/Bubbles Autoclicker" || fail "Could not set app executable permission."

if command -v plutil >/dev/null 2>&1; then
  run_step "4/6  Validating Info.plist" plutil -lint "$CONTENTS/Info.plist"
else
  echo "4/6  plutil unavailable; skipped." | tee -a "$LOG"
fi

echo ""
echo "5/6  Creating app icon" | tee -a "$LOG"
ICON_SOURCE="$ROOT/Resources/BubblesIcon.png"
if [ -f "$ICON_SOURCE" ] && command -v iconutil >/dev/null 2>&1 && command -v sips >/dev/null 2>&1; then
  ICONSET="$ROOT/.build/BubblesIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"

  for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>>"$LOG" \
      || fail "Could not create ${size}px icon."
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>>"$LOG" \
      || fail "Could not create Retina icon for ${size}px."
  done

  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/BubblesIcon.icns" >>"$LOG" 2>&1 \
    || fail "iconutil could not create the app icon."
else
  echo "Icon tools unavailable; using default app icon." | tee -a "$LOG"
fi

echo ""
echo "6/6  Signing local app" | tee -a "$LOG"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" 2>&1 | tee -a "$LOG"
  status=${PIPESTATUS[0]}
  [ "$status" -eq 0 ] || fail "Local ad-hoc signing failed."
else
  echo "codesign unavailable; app left unsigned." | tee -a "$LOG"
fi

# A locally generated app can inherit quarantine from files extracted from a
# downloaded zip. Clear quarantine on the generated app only.
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
fi

echo ""
echo "============================================================"
echo "BUILD COMPLETE"
echo "============================================================"
echo "Created:"
echo "  $APP"
echo ""
echo "Finder will open the dist folder now."
echo "On first launch grant Accessibility + Input Monitoring."
echo "If macOS blocks the first launch, right-click the app -> Open."
open "$ROOT/dist" >/dev/null 2>&1 || true
pause_and_exit 0
