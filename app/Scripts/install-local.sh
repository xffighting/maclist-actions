#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_NAME="$0"
DESTINATION_ROOT="${MACLIST_INSTALL_DIR:-$HOME/Applications}"
EXPECTED_BUNDLE_ID="com.xffighting.maclist"
EXPECTED_VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/../VERSION")"
SHOULD_LAUNCH=0
TEST_MODE="${MACLIST_INSTALL_TEST_MODE:-0}"

usage() {
  print "Usage: $SCRIPT_NAME [--launch] [--destination DIR]"
  print "Installs MacList.app locally. It is not launched unless --launch is supplied."
}

while (( $# > 0 )); do
  case "$1" in
    --launch)
      SHOULD_LAUNCH=1
      shift
      ;;
    --destination)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DESTINATION_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$EXPECTED_VERSION" ]] || {
  print -u2 "VERSION is empty; refusing to install."
  exit 2
}

if [[ -L "$DESTINATION_ROOT" ]]; then
  print -u2 "Destination must be a real directory, not a symlink: $DESTINATION_ROOT"
  exit 2
elif [[ -e "$DESTINATION_ROOT" ]]; then
  if [[ ! -d "$DESTINATION_ROOT" ]]; then
    print -u2 "Destination must be a real directory, not a file: $DESTINATION_ROOT"
    exit 2
  fi
else
  /bin/mkdir -p -m 700 "$DESTINATION_ROOT"
fi

DESTINATION_ROOT="$(cd -P "$DESTINATION_ROOT" && pwd)"
if [[ "$(/usr/bin/stat -f '%u' "$DESTINATION_ROOT")" != "$(/usr/bin/id -u)" ]]; then
  print -u2 "Destination must be owned by the current user: $DESTINATION_ROOT"
  exit 2
fi
if [[ ! -w "$DESTINATION_ROOT" || ! -x "$DESTINATION_ROOT" ]]; then
  print -u2 "Destination must be writable and searchable: $DESTINATION_ROOT"
  exit 2
fi

if [[ "$TEST_MODE" == "1" ]]; then
  (( SHOULD_LAUNCH == 0 )) || {
    print -u2 "Test mode never launches MacList."
    exit 2
  }
  TEST_TEMP_ROOT="$(cd -P "${TMPDIR:-/tmp}" && pwd)"
  case "$DESTINATION_ROOT/" in
    "$TEST_TEMP_ROOT"/*) ;;
    *)
      print -u2 "Test mode destination must stay inside TMPDIR."
      exit 2
      ;;
  esac
elif [[ "$TEST_MODE" != "0" ]]; then
  print -u2 "MACLIST_INSTALL_TEST_MODE must be 0 or 1."
  exit 2
elif /usr/bin/pgrep -x MacList >/dev/null 2>&1; then
  print -u2 "MacList is already running. Quit it from the menu bar before installing or updating."
  exit 2
fi

DESTINATION_APP="$DESTINATION_ROOT/MacList.app"
STAGING_APP="$DESTINATION_ROOT/.MacList.installing.app"
BACKUP_APP="$DESTINATION_ROOT/.MacList.previous.app"
LOCK_DIR="$DESTINATION_ROOT/.MacList.install.lock"

bundle_identity() {
  /usr/bin/stat -f '%d:%i' "$1" 2>/dev/null
}

bundle_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null
}

verify_managed_bundle() {
  local app_path="$1"
  local required_version="${2:-}"
  local bundle_id bundle_version signature_details signature_identifier

  [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
  [[ "$(/usr/bin/stat -f '%u' "$app_path" 2>/dev/null)" == "$(/usr/bin/id -u)" ]] || return 1
  [[ -f "$app_path/Contents/Info.plist" && ! -L "$app_path/Contents/Info.plist" ]] || return 1
  [[ -f "$app_path/Contents/MacOS/MacList" && ! -L "$app_path/Contents/MacOS/MacList" ]] || return 1
  [[ -x "$app_path/Contents/MacOS/MacList" ]] || return 1
  /usr/bin/plutil -lint "$app_path/Contents/Info.plist" >/dev/null || return 1

  bundle_id="$(bundle_plist_value "$app_path" CFBundleIdentifier)" || return 1
  bundle_version="$(bundle_plist_value "$app_path" CFBundleShortVersionString)" || return 1
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" && -n "$bundle_version" ]] || return 1
  [[ -z "$required_version" || "$bundle_version" == "$required_version" ]] || return 1

  /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 || return 1
  signature_details="$(/usr/bin/codesign -d --verbose=4 "$app_path" 2>&1)" || return 1
  signature_identifier="$(print -r -- "$signature_details" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
  [[ "$signature_identifier" == "$EXPECTED_BUNDLE_ID" ]] || return 1

}

remove_managed_bundle() {
  local app_path="$1"
  local expected_identity="${2:-}"

  verify_managed_bundle "$app_path" || {
    print -u2 "Refusing to remove an unverified app bundle: $app_path"
    return 1
  }
  if [[ -n "$expected_identity" && "$(bundle_identity "$app_path")" != "$expected_identity" ]]; then
    print -u2 "Refusing to remove an app bundle that changed during installation: $app_path"
    return 1
  fi
  /bin/rm -rf "$app_path"
}

remove_tracked_bundle() {
  local app_path="$1"
  local expected_identity="$2"

  [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
  [[ "$(/usr/bin/stat -f '%u' "$app_path" 2>/dev/null)" == "$(/usr/bin/id -u)" ]] || return 1
  [[ -n "$expected_identity" && "$(bundle_identity "$app_path")" == "$expected_identity" ]] || {
    print -u2 "Refusing to remove a transaction bundle that changed identity: $app_path"
    return 1
  }
  /bin/rm -rf "$app_path"
}

LOCK_PID_TEMP="$LOCK_DIR/pid.$$"
WORK_DIR=""
SOURCE_APP=""
PREVIOUS_IDENTITY=""
NEW_IDENTITY=""
LOCK_IDENTITY=""
LOCK_ACQUIRED=0
LOCK_PUBLISHED=0
ORIGINAL_PRESENT=0
REPLACEMENT_STARTED=0
BACKUP_TRACKED=0
HAD_PREVIOUS=0
STAGING_TRACKED=0
INSTALLED_NEW=0
COMMITTED=0

release_lock() {
  local recorded_pid

  (( LOCK_ACQUIRED )) || return 0
  [[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || {
    print -u2 "Installer lock disappeared or changed type."
    return 1
  }
  [[ "$(bundle_identity "$LOCK_DIR")" == "$LOCK_IDENTITY" ]] || {
    print -u2 "Installer lock identity changed; it was left untouched."
    return 1
  }
  if (( ! LOCK_PUBLISHED )) && [[ ! -e "$LOCK_DIR/pid" ]]; then
    /bin/rm -f "$LOCK_PID_TEMP" || return 1
    /bin/rmdir "$LOCK_DIR" || return 1
    LOCK_ACQUIRED=0
    return 0
  fi
  [[ -f "$LOCK_DIR/pid" && ! -L "$LOCK_DIR/pid" ]] || {
    print -u2 "Installer lock PID record changed; it was left untouched."
    return 1
  }
  recorded_pid="$(/bin/cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  [[ "$recorded_pid" == "$$" ]] || {
    print -u2 "Installer lock ownership changed; it was left untouched."
    return 1
  }
  /bin/rm -f "$LOCK_DIR/pid" "$LOCK_PID_TEMP" || return 1
  /bin/rmdir "$LOCK_DIR" || return 1
  LOCK_ACQUIRED=0
  LOCK_PUBLISHED=0
  return 0
}

rollback_installation() {
  local current_identity

  if (( INSTALLED_NEW )) && [[ -e "$DESTINATION_APP" ]]; then
    current_identity="$(bundle_identity "$DESTINATION_APP")"
    if [[ -n "$NEW_IDENTITY" && "$current_identity" == "$NEW_IDENTITY" ]]; then
      /bin/mv "$DESTINATION_APP" "$STAGING_APP" || return 1
    else
      print -u2 "Rollback could not move a destination bundle that changed concurrently."
      return 1
    fi
  fi

  if (( REPLACEMENT_STARTED && ORIGINAL_PRESENT )); then
    if (( HAD_PREVIOUS )); then
      [[ -e "$BACKUP_APP" && ! -e "$DESTINATION_APP" ]] || {
        print -u2 "Rollback requires the tracked backup and an empty destination."
        return 1
      }
      [[ "$(bundle_identity "$BACKUP_APP")" == "$PREVIOUS_IDENTITY" ]] || {
        print -u2 "Rollback backup identity changed; it was left untouched."
        return 1
      }
      /bin/mv "$BACKUP_APP" "$DESTINATION_APP" || return 1
      BACKUP_TRACKED=0
      verify_managed_bundle "$DESTINATION_APP" || {
        print -u2 "Rollback restored the prior bundle, but its verification failed."
        return 1
      }
    else
      [[ -e "$DESTINATION_APP" && ! -e "$BACKUP_APP" ]] || {
        print -u2 "Rollback could not prove that the original destination remained untouched."
        return 1
      }
      [[ "$(bundle_identity "$DESTINATION_APP")" == "$PREVIOUS_IDENTITY" ]] || {
        print -u2 "Rollback found a different bundle at the original destination."
        return 1
      }
      verify_managed_bundle "$DESTINATION_APP" || return 1
    fi
  elif (( REPLACEMENT_STARTED )); then
    [[ ! -e "$DESTINATION_APP" && ! -e "$BACKUP_APP" ]] || {
      print -u2 "Rollback of a fresh install left an unexpected destination or backup."
      return 1
    }
  fi

  if (( STAGING_TRACKED )) && [[ -e "$STAGING_APP" ]]; then
    if [[ "$(bundle_identity "$STAGING_APP")" == "$NEW_IDENTITY" ]]; then
      remove_tracked_bundle "$STAGING_APP" "$NEW_IDENTITY" || return 1
      STAGING_TRACKED=0
    else
      print -u2 "The failed staged bundle changed or no longer verifies; it was left untouched."
      return 1
    fi
  fi

  if (( STAGING_TRACKED )) && [[ -e "$STAGING_APP" ]]; then
    print -u2 "Rollback left a tracked staging bundle."
    return 1
  fi
  if (( BACKUP_TRACKED )) && [[ -e "$BACKUP_APP" ]]; then
    print -u2 "Rollback left a tracked backup bundle."
    return 1
  fi
  return 0
}

finish() {
  local exit_code=$?
  local rollback_code=0
  local lock_code=0

  trap - EXIT INT TERM HUP
  set +e
  if (( exit_code != 0 && COMMITTED == 0 )); then
    rollback_installation
    rollback_code=$?
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" && ! -L "$WORK_DIR" ]]; then
    /bin/rm -rf "$WORK_DIR"
  fi
  release_lock
  lock_code=$?
  if (( rollback_code != 0 )); then
    print -u2 "Installation failed and automatic rollback was incomplete; managed recovery files were left untouched."
    exit 70
  fi
  if (( lock_code != 0 )); then
    print -u2 "Installer lock cleanup failed; the installation result is preserved but requires manual lock cleanup."
    exit 71
  fi
  exit "$exit_code"
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -L "$LOCK_DIR" || ! -d "$LOCK_DIR" ]]; then
    print -u2 "Refusing an unsafe installer lock: $LOCK_DIR"
    exit 2
  fi
  if [[ "$(/usr/bin/stat -f '%u' "$LOCK_DIR" 2>/dev/null)" != "$(/usr/bin/id -u)" ]]; then
    print -u2 "Refusing an installer lock not owned by the current user."
    exit 2
  fi
  if [[ ! -e "$LOCK_DIR/pid" ]]; then
    print -u2 "Another MacList installer is acquiring the lock; the empty lock was left untouched."
    exit 2
  elif [[ -L "$LOCK_DIR/pid" || ! -f "$LOCK_DIR/pid" ]]; then
    print -u2 "The installer lock PID record is unsafe; it was left untouched."
    exit 2
  fi
  existing_pid="$(/bin/cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -z "$existing_pid" ]]; then
    print -u2 "Another MacList installer is publishing its PID; the lock was left untouched."
  elif [[ "$existing_pid" != <-> ]]; then
    print -u2 "The installer lock has invalid ownership data; it was left untouched."
  elif /bin/kill -0 "$existing_pid" 2>/dev/null; then
    print -u2 "Another MacList installation is already running."
  else
    print -u2 "A stale installer lock exists for PID $existing_pid; remove it manually after checking no installer is running."
  fi
  exit 2
fi
LOCK_ACQUIRED=1
LOCK_IDENTITY="$(bundle_identity "$LOCK_DIR")"
print -r -- "$$" > "$LOCK_PID_TEMP"
/bin/mv "$LOCK_PID_TEMP" "$LOCK_DIR/pid"
LOCK_PUBLISHED=1

for managed_path in "$DESTINATION_APP" "$STAGING_APP" "$BACKUP_APP"; do
  if [[ -L "$managed_path" || ( -e "$managed_path" && ! -d "$managed_path" ) ]]; then
    print -u2 "Refusing an unsafe app path: $managed_path"
    exit 2
  fi
done

if [[ -e "$DESTINATION_APP" ]] && ! verify_managed_bundle "$DESTINATION_APP"; then
  print -u2 "An existing MacList.app is not a valid signed $EXPECTED_BUNDLE_ID bundle; it was left untouched."
  exit 2
fi

if [[ -e "$BACKUP_APP" ]]; then
  print -u2 "A previous installer backup still exists; it was left untouched: $BACKUP_APP"
  exit 2
fi

if [[ -e "$STAGING_APP" ]]; then
  print -u2 "A previous installer staging path still exists; it was left untouched: $STAGING_APP"
  exit 2
fi

WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/maclist-install.XXXXXX")"
PRIVATE_APP_OUTPUT_DIR="$WORK_DIR/app-output"
APP_OUTPUT_DIR="$PRIVATE_APP_OUTPUT_DIR" "$ROOT/Scripts/build-app.sh" release >/dev/null
SOURCE_APP="$PRIVATE_APP_OUTPUT_DIR/MacList.app"
verify_managed_bundle "$SOURCE_APP" "$EXPECTED_VERSION" || {
  print -u2 "Built MacList.app failed bundle identifier, version, executable structure, or signature verification."
  exit 1
}

if ! /usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"; then
  if [[ -d "$STAGING_APP" && ! -L "$STAGING_APP" ]]; then
    NEW_IDENTITY="$(bundle_identity "$STAGING_APP")"
    STAGING_TRACKED=1
  fi
  print -u2 "Copying MacList.app into installer staging failed."
  exit 1
fi
NEW_IDENTITY="$(bundle_identity "$STAGING_APP")"
STAGING_TRACKED=1
verify_managed_bundle "$STAGING_APP" "$EXPECTED_VERSION" || {
  print -u2 "Staged MacList.app failed bundle identifier, version, executable structure, or signature verification."
  exit 1
}
if [[ -e "$DESTINATION_APP" ]]; then
  ORIGINAL_PRESENT=1
  PREVIOUS_IDENTITY="$(bundle_identity "$DESTINATION_APP")"
fi
REPLACEMENT_STARTED=1
if (( ORIGINAL_PRESENT )); then
  if /bin/mv "$DESTINATION_APP" "$BACKUP_APP"; then
    HAD_PREVIOUS=1
    BACKUP_TRACKED=1
  elif [[ -e "$BACKUP_APP" && ! -e "$DESTINATION_APP" ]]; then
    HAD_PREVIOUS=1
    BACKUP_TRACKED=1
    print -u2 "Moving the prior MacList.app into backup reported a failure."
    exit 1
  else
    print -u2 "Could not preserve the prior MacList.app before replacement."
    exit 1
  fi
fi

if /bin/mv "$STAGING_APP" "$DESTINATION_APP"; then
  INSTALLED_NEW=1
elif [[ -e "$DESTINATION_APP" && "$(bundle_identity "$DESTINATION_APP")" == "$NEW_IDENTITY" ]]; then
  INSTALLED_NEW=1
  print -u2 "Moving the staged MacList.app into place reported a failure."
  exit 1
else
  print -u2 "Could not move the staged MacList.app into place."
  exit 1
fi
[[ "$(bundle_identity "$DESTINATION_APP")" == "$NEW_IDENTITY" ]] || {
  print -u2 "Installed bundle identity changed during replacement."
  exit 1
}

if [[ "$TEST_MODE" == "1" && "${MACLIST_INSTALL_TEST_FAIL_AFTER_SWAP:-0}" == "1" ]]; then
  print -u2 "Intentional test failure after app replacement."
  exit 86
fi

verify_managed_bundle "$DESTINATION_APP" "$EXPECTED_VERSION" || {
  print -u2 "Installed MacList.app failed post-replacement verification."
  exit 1
}

if (( HAD_PREVIOUS )); then
  trap '' INT TERM HUP
  if ! remove_managed_bundle "$BACKUP_APP" "$PREVIOUS_IDENTITY"; then
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    print -u2 "The new app verified, but the prior backup could not be removed; rolling back."
    exit 1
  fi
  BACKUP_TRACKED=0
  COMMITTED=1
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
else
  COMMITTED=1
fi

print "Installed: $DESTINATION_APP"
if (( SHOULD_LAUNCH )); then
  /usr/bin/open -gj "$DESTINATION_APP"
  print "Launched MacList in the background."
else
  print "Not launched. Run again with --launch when you want to start it."
fi
