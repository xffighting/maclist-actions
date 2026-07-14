#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT/outputs}"
MACLIST_APP="$OUTPUT_DIR/MacList.app"
HARNESS_APP="$OUTPUT_DIR/DialogHarness.app"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

mkdir -p "$OUTPUT_DIR"
rm -rf "$MACLIST_APP" "$HARNESS_APP"

mkdir -p "$MACLIST_APP/Contents/MacOS" "$MACLIST_APP/Contents/Resources"
install -m 0755 "$BIN_DIR/MacList" "$MACLIST_APP/Contents/MacOS/MacList"
install -m 0644 "$ROOT/Resources/Info.plist" "$MACLIST_APP/Contents/Info.plist"

mkdir -p "$HARNESS_APP/Contents/MacOS" "$HARNESS_APP/Contents/Resources"
install -m 0755 "$BIN_DIR/DialogHarness" "$HARNESS_APP/Contents/MacOS/DialogHarness"
install -m 0644 "$ROOT/Resources/DialogHarness-Info.plist" "$HARNESS_APP/Contents/Info.plist"

plutil -lint "$MACLIST_APP/Contents/Info.plist" >/dev/null
plutil -lint "$HARNESS_APP/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$MACLIST_APP" >/dev/null
codesign --force --deep --sign - "$HARNESS_APP" >/dev/null

echo "$MACLIST_APP"
echo "$HARNESS_APP"
