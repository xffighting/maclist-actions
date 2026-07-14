#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/Scripts/smoke-test.sh"

if swift -e 'import XCTest' >/dev/null 2>&1; then
  swift test --package-path "$ROOT"
else
  echo "XCTest unavailable in Command Line Tools; GitHub Actions runs the XCTest suite."
fi

"$ROOT/Scripts/build-app.sh" release

plutil -lint "$ROOT/outputs/MacList.app/Contents/Info.plist"
codesign --verify --deep --strict "$ROOT/outputs/MacList.app"
"$ROOT/outputs/MacList.app/Contents/MacOS/MacList" --doctor
