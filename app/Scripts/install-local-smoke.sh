#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/Scripts/install-local.sh"
EXPECTED_BUNDLE_ID="com.xffighting.maclist"
EXPECTED_VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/../VERSION")"
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/maclist-installer-smoke.XXXXXX")"
TEST_TMP="$TEST_ROOT/tmp"
LOG_PATH="$TEST_ROOT/installer.log"
POISON_OUTPUT="$TEST_ROOT/external-output-must-stay-unused"

finish() {
  local exit_code=$?

  trap - EXIT INT TERM HUP
  set +e
  if [[ -d "$TEST_ROOT" && ! -L "$TEST_ROOT" ]]; then
    /bin/rm -rf "$TEST_ROOT"
  fi
  exit "$exit_code"
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

/bin/mkdir -m 700 "$TEST_TMP"

verify_installed_bundle() {
  local app_path="$1"
  local info_plist="$app_path/Contents/Info.plist"
  local executable="$app_path/Contents/MacOS/MacList"
  local bundle_id bundle_version signature_details signature_identifier

  [[ -d "$app_path" && ! -L "$app_path" ]]
  /usr/bin/plutil -lint "$info_plist" >/dev/null
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]]
  [[ "$bundle_version" == "$EXPECTED_VERSION" ]]
  [[ -x "$executable" && ! -L "$executable" ]]
  /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null
  signature_details="$(/usr/bin/codesign -d --verbose=4 "$app_path" 2>&1)"
  signature_identifier="$(print -r -- "$signature_details" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
  [[ "$signature_identifier" == "$EXPECTED_BUNDLE_ID" ]]
}

assert_no_transaction_artifacts() {
  local destination="$1"

  [[ ! -e "$destination/.MacList.installing.app" ]]
  [[ ! -e "$destination/.MacList.previous.app" ]]
  [[ ! -e "$destination/.MacList.install.lock" ]]
}

APPLICATIONS_DIR="$TEST_TMP/applications"
/bin/mkdir -m 700 "$APPLICATIONS_DIR"

TMPDIR="$TEST_TMP/" \
MACLIST_INSTALL_TEST_MODE=1 \
APP_OUTPUT_DIR="$POISON_OUTPUT" \
/bin/zsh "$INSTALLER" --destination "$APPLICATIONS_DIR" >"$LOG_PATH" 2>&1 || {
  /bin/cat "$LOG_PATH" >&2
  exit 1
}

INSTALLED_APP="$APPLICATIONS_DIR/MacList.app"
verify_installed_bundle "$INSTALLED_APP"
assert_no_transaction_artifacts "$APPLICATIONS_DIR"
[[ ! -e "$POISON_OUTPUT" ]]

ROLLBACK_MARKER="$INSTALLED_APP/Contents/Resources/installer-rollback-marker.txt"
print -r -- "prior-installation-must-be-restored" > "$ROLLBACK_MARKER"
/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.xffighting.maclist"' \
  "$INSTALLED_APP" >/dev/null 2>&1
verify_installed_bundle "$INSTALLED_APP"

failure_code=0
if TMPDIR="$TEST_TMP/" \
  MACLIST_INSTALL_TEST_MODE=1 \
  MACLIST_INSTALL_TEST_FAIL_AFTER_SWAP=1 \
  APP_OUTPUT_DIR="$POISON_OUTPUT" \
  /bin/zsh "$INSTALLER" --destination "$APPLICATIONS_DIR" >"$LOG_PATH" 2>&1; then
  print -u2 "Installer rollback smoke unexpectedly succeeded."
  exit 1
else
  failure_code=$?
fi
[[ "$failure_code" == "86" ]] || {
  /bin/cat "$LOG_PATH" >&2
  print -u2 "Expected rollback test exit 86, got $failure_code."
  exit 1
}

verify_installed_bundle "$INSTALLED_APP"
[[ "$(< "$ROLLBACK_MARKER")" == "prior-installation-must-be-restored" ]]
assert_no_transaction_artifacts "$APPLICATIONS_DIR"
[[ ! -e "$POISON_OUTPUT" ]]

FOREIGN_DIR="$TEST_TMP/foreign-applications"
/bin/mkdir -m 700 -p "$FOREIGN_DIR/MacList.app"
print -r -- "do-not-delete" > "$FOREIGN_DIR/MacList.app/sentinel"
if TMPDIR="$TEST_TMP/" MACLIST_INSTALL_TEST_MODE=1 \
  /bin/zsh "$INSTALLER" --destination "$FOREIGN_DIR" >"$LOG_PATH" 2>&1; then
  print -u2 "Installer accepted an unmanaged MacList.app."
  exit 1
fi
[[ "$(< "$FOREIGN_DIR/MacList.app/sentinel")" == "do-not-delete" ]]
[[ ! -e "$FOREIGN_DIR/.MacList.install.lock" ]]

LOCK_DIR_TEST="$TEST_TMP/lock-applications"
/bin/mkdir -m 700 "$LOCK_DIR_TEST"
/bin/mkdir "$LOCK_DIR_TEST/.MacList.install.lock"
if TMPDIR="$TEST_TMP/" MACLIST_INSTALL_TEST_MODE=1 \
  /bin/zsh "$INSTALLER" --destination "$LOCK_DIR_TEST" >"$LOG_PATH" 2>&1; then
  print -u2 "Installer accepted a lock whose PID was not yet published."
  exit 1
fi
[[ -d "$LOCK_DIR_TEST/.MacList.install.lock" ]]
[[ -z "$(/bin/ls -A "$LOCK_DIR_TEST/.MacList.install.lock")" ]]
/bin/rmdir "$LOCK_DIR_TEST/.MacList.install.lock"

print "PASS local installer success, private-output, rollback, ownership, and lock tests"
