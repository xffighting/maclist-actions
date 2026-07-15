#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_BUNDLE_ID="com.xffighting.maclist"
EXPECTED_VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/../VERSION")"
VERIFY_WORK_DIR=""

finish() {
  local exit_code=$?

  trap - EXIT INT TERM HUP
  set +e
  if [[ -n "$VERIFY_WORK_DIR" && -d "$VERIFY_WORK_DIR" && ! -L "$VERIFY_WORK_DIR" ]]; then
    /bin/rm -rf "$VERIFY_WORK_DIR"
  fi
  exit "$exit_code"
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

"$ROOT/Scripts/all-smoke-tests.sh"

if [[ "${MACLIST_SKIP_XCTEST:-0}" == "1" ]]; then
  echo "XCTest skipped because MACLIST_SKIP_XCTEST=1."
elif [[ "$(xcode-select -p 2>/dev/null || true)" == *"/Xcode.app/Contents/Developer"* ]] \
  && swift -e 'import XCTest' >/dev/null 2>&1; then
  swift test --package-path "$ROOT"
else
  echo "Full Xcode unavailable; GitHub Actions runs the XCTest suite."
fi

[[ -n "$EXPECTED_VERSION" ]] || {
  echo "VERSION is empty" >&2
  exit 1
}

VERIFY_WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/maclist-verify.XXXXXX")"
PRIVATE_APP_OUTPUT_DIR="$VERIFY_WORK_DIR/app-output"
APP_OUTPUT_DIR="$PRIVATE_APP_OUTPUT_DIR" "$ROOT/Scripts/build-app.sh" release >/dev/null

APP_PATH="$PRIVATE_APP_OUTPUT_DIR/MacList.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/MacList"
RAW_BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
RAW_EXECUTABLE="$RAW_BIN_DIR/MacList"

[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]]
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]]
[[ -x "$EXECUTABLE" && ! -L "$EXECUTABLE" ]]

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || {
  echo "Bundle identifier mismatch: expected '$EXPECTED_BUNDLE_ID', got '$bundle_id'" >&2
  exit 1
}
[[ "$bundle_version" == "$EXPECTED_VERSION" ]] || {
  echo "Bundle version mismatch: expected '$EXPECTED_VERSION', got '$bundle_version'" >&2
  exit 1
}

expected_executable_version="MacList $EXPECTED_VERSION"
actual_executable_version="$("$RAW_EXECUTABLE" --version)"
[[ "$actual_executable_version" == "$expected_executable_version" ]] || {
  echo "Executable version mismatch: expected '$expected_executable_version', got '$actual_executable_version'" >&2
  exit 1
}

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
signature_details="$(/usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1)"
signature_identifier="$(print -r -- "$signature_details" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
[[ "$signature_identifier" == "$EXPECTED_BUNDLE_ID" ]] || {
  echo "Signature identifier mismatch: expected '$EXPECTED_BUNDLE_ID', got '$signature_identifier'" >&2
  exit 1
}

if [[ "${MACLIST_CODE_SIGN_IDENTITY:--}" == "-" ]]; then
  requirement="$(/usr/bin/codesign -d -r- "$APP_PATH" 2>&1)"
  [[ "$requirement" == *'designated => identifier "com.xffighting.maclist"'* ]] || {
    echo "MacList local signature does not have a stable designated requirement" >&2
    exit 1
  }
fi

"$RAW_EXECUTABLE" --doctor
