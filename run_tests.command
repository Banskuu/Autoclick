#!/bin/bash
ROOT="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
cd "$ROOT" || exit 1

echo "Bubbles Autoclicker tests"
echo "========================="

if command -v xcrun >/dev/null 2>&1; then
  SWIFT="$(xcrun --find swift 2>/dev/null)"
else
  SWIFT="$(command -v swift 2>/dev/null)"
fi

if [ -z "$SWIFT" ]; then
  echo "Swift not found. Install tools with: xcode-select --install"
  echo "Press any key to close..."
  IFS= read -r -n 1 _
  exit 1
fi

"$SWIFT" test
status=$?
echo ""
[ "$status" -eq 0 ] && echo "Tests passed." || echo "Tests FAILED."
echo "Press any key to close..."
IFS= read -r -n 1 _
exit "$status"
