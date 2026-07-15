#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT/outputs}"
MACLIST_APP="$OUTPUT_DIR/MacList.app"
HARNESS_APP="$OUTPUT_DIR/DialogHarness.app"
CODE_SIGN_IDENTITY="${MACLIST_CODE_SIGN_IDENTITY:--}"
EXPECTED_VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/../VERSION")"

[[ -n "$EXPECTED_VERSION" ]] || {
    print -u2 "VERSION is empty; refusing to build an app bundle."
    exit 1
}

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
ACTUAL_EXECUTABLE_VERSION="$("$BIN_DIR/MacList" --version)"
[[ "$ACTUAL_EXECUTABLE_VERSION" == "MacList $EXPECTED_VERSION" ]] || {
    print -u2 "Executable version mismatch: expected 'MacList $EXPECTED_VERSION', got '$ACTUAL_EXECUTABLE_VERSION'"
    exit 1
}

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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MACLIST_APP/Contents/Info.plist")" == "$EXPECTED_VERSION" ]] || {
    print -u2 "MacList Info.plist version does not match VERSION."
    exit 1
}

sign_app() {
    local app_path="$1"
    local bundle_id="$2"

    if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
        # Keep a stable designated requirement for local development builds.
        # A plain ad-hoc signature defaults to a CDHash requirement, which
        # changes after every rebuild and silently invalidates macOS TCC grants.
        codesign \
            --force \
            --deep \
            --sign - \
            --requirements "=designated => identifier \"$bundle_id\"" \
            "$app_path" >/dev/null
    else
        codesign \
            --force \
            --deep \
            --sign "$CODE_SIGN_IDENTITY" \
            "$app_path" >/dev/null
    fi
}

sign_app "$MACLIST_APP" "com.xffighting.maclist"
sign_app "$HARNESS_APP" "com.xffighting.maclist.dialog-harness"

echo "$MACLIST_APP"
echo "$HARNESS_APP"
