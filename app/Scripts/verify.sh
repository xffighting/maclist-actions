#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/Scripts/all-smoke-tests.sh"

if [[ "${MACLIST_SKIP_XCTEST:-0}" == "1" ]]; then
  echo "XCTest skipped because MACLIST_SKIP_XCTEST=1."
elif [[ "$(xcode-select -p 2>/dev/null || true)" == *"/Xcode.app/Contents/Developer"* ]] \
  && swift -e 'import XCTest' >/dev/null 2>&1; then
  swift test --package-path "$ROOT"
else
  echo "Full Xcode unavailable; GitHub Actions runs the XCTest suite."
fi

"$ROOT/Scripts/build-app.sh" release

plutil -lint "$ROOT/outputs/MacList.app/Contents/Info.plist"
codesign --verify --deep --strict "$ROOT/outputs/MacList.app"

if [[ "${MACLIST_CODE_SIGN_IDENTITY:--}" == "-" ]]; then
  requirement="$(codesign -d -r- "$ROOT/outputs/MacList.app" 2>&1)"
  [[ "$requirement" == *'designated => identifier "com.xffighting.maclist"'* ]] || {
    echo "MacList local signature does not have a stable designated requirement" >&2
    exit 1
  }
fi

"$ROOT/outputs/MacList.app/Contents/MacOS/MacList" --doctor
