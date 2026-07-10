#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$ROOT/scripts"
TARGET_DIR="${MACLIST_TARGET_DIR:-$HOME/Library/Application Scripts/Cling}"
STATE_DIR="${MACLIST_STATE_DIR:-$HOME/Library/Application Support/MacList Custom}"
PREF_DOMAIN="${MACLIST_PREF_DOMAIN:-com.lowtechguys.Cling}"
EXPECTED_VERSION="2.6.5"
EXPECTED_BUNDLE_ID="com.lowtechguys.Cling"
EXPECTED_TEAM_ID="RDDXV84A73"

ACTIVE_FILE="$STATE_DIR/active"
INSTALLING_FILE="$STATE_DIR/installing"
FILES_BEFORE="$STATE_DIR/files.before.tsv"
PREFS_BEFORE="$STATE_DIR/preferences.before.tsv"
BACKUP_DIR="$STATE_DIR/original-scripts"
MANIFEST="$STATE_DIR/installed-files.txt"
TARGET_DIR_BEFORE="$STATE_DIR/target-dir.before.tsv"

typeset -a PREF_KEYS=(
  enableSentry
  honorGitignore
  disableAutomaticVolumeIndexing
  showActionRow
  showFilePreview
  showSearchHints
)

die() {
  /usr/bin/printf 'MacList install stopped: %s\n' "$1" >&2
  exit 1
}

find_app() {
  if [[ -n "${MACLIST_APP_PATH:-}" && -d "${MACLIST_APP_PATH:-}" ]]; then
    /usr/bin/printf '%s\n' "${MACLIST_APP_PATH:-}"
  elif [[ -d /Applications/Cling.app ]]; then
    /usr/bin/printf '%s\n' /Applications/Cling.app
  elif [[ -d "$HOME/Applications/Cling.app" ]]; then
    /usr/bin/printf '%s\n' "$HOME/Applications/Cling.app"
  fi
}

verify_app() {
  local APP VERSION BUNDLE_ID TEAM_ID
  APP="$(find_app)"
  [[ -n "$APP" ]] || die "official Cling is not installed in /Applications or ~/Applications"
  /usr/bin/codesign --verify --deep --strict "$APP" || die "Cling signature verification failed"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)"
  TEAM_ID="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  [[ "$VERSION" == "$EXPECTED_VERSION" ]] || die "expected Cling $EXPECTED_VERSION, found $VERSION"
  [[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || die "unexpected bundle identifier: $BUNDLE_ID"
  [[ "$TEAM_ID" == "$EXPECTED_TEAM_ID" ]] || die "unexpected signing team: $TEAM_ID"
}

if [[ "${MACLIST_SKIP_APP_CHECK:-0}" != 1 ]]; then
  verify_app
fi

/bin/mkdir -p "$STATE_DIR"
/bin/chmod 700 "$STATE_DIR"

if [[ -f "$INSTALLING_FILE" && ! -f "$ACTIVE_FILE" ]]; then
  die "a previous install was interrupted; run Customization/uninstall.sh before retrying"
fi

if [[ -f "$ACTIVE_FILE" ]]; then
  [[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]] || die "custom scripts directory is missing or unsafe"
  /bin/chmod 700 "$TARGET_DIR"
  for SOURCE in "$SOURCE_DIR"/MacList*; do
    NAME="${SOURCE:t}"
    TARGET="$TARGET_DIR/$NAME"
    if [[ -e "$TARGET" ]] && ! /usr/bin/cmp -s "$SOURCE" "$TARGET"; then
      die "$NAME was edited after installation; uninstall first so the original can be restored safely"
    fi
  done
else
  [[ ! -e "$FILES_BEFORE" && ! -e "$PREFS_BEFORE" && ! -e "$TARGET_DIR_BEFORE" && ! -e "$BACKUP_DIR" ]] ||
    die "unresolved backup state exists; run Customization/uninstall.sh before retrying"

  [[ ! -L "$TARGET_DIR" ]] || die "custom scripts directory must not be a symbolic link"
  if [[ -d "$TARGET_DIR" ]]; then
    TARGET_MODE="$(/usr/bin/stat -f %Lp "$TARGET_DIR")"
    /usr/bin/printf 'present\t%s\n' "$TARGET_MODE" > "$TARGET_DIR_BEFORE"
  elif [[ -e "$TARGET_DIR" ]]; then
    die "custom scripts path exists but is not a directory"
  else
    /usr/bin/printf 'absent\t-\n' > "$TARGET_DIR_BEFORE"
    /bin/mkdir -p "$TARGET_DIR"
  fi
  /bin/chmod 700 "$TARGET_DIR"

  /bin/mkdir -p "$BACKUP_DIR"
  /bin/chmod 700 "$BACKUP_DIR"
  : > "$FILES_BEFORE"
  : > "$PREFS_BEFORE"
  /bin/chmod 600 "$FILES_BEFORE" "$PREFS_BEFORE" "$TARGET_DIR_BEFORE"
  /usr/bin/touch "$INSTALLING_FILE"
  /bin/chmod 600 "$INSTALLING_FILE"

  for SOURCE in "$SOURCE_DIR"/MacList*; do
    NAME="${SOURCE:t}"
    TARGET="$TARGET_DIR/$NAME"
    if [[ -e "$TARGET" ]]; then
      /usr/bin/ditto "$TARGET" "$BACKUP_DIR/$NAME"
      /usr/bin/printf '%s\tpresent\n' "$NAME" >> "$FILES_BEFORE"
    else
      /usr/bin/printf '%s\tabsent\n' "$NAME" >> "$FILES_BEFORE"
    fi
  done

  for KEY in "${PREF_KEYS[@]}"; do
    if VALUE="$(/usr/bin/defaults read "$PREF_DOMAIN" "$KEY" 2>/dev/null)"; then
      [[ "$VALUE" == 0 || "$VALUE" == 1 ]] || die "preference $KEY is not a Boolean; no changes were made"
      /usr/bin/printf '%s\tpresent\t%s\n' "$KEY" "$VALUE" >> "$PREFS_BEFORE"
    else
      /usr/bin/printf '%s\tabsent\t-\n' "$KEY" >> "$PREFS_BEFORE"
    fi
  done
fi

: > "$MANIFEST"
/bin/chmod 600 "$MANIFEST"
for SOURCE in "$SOURCE_DIR"/MacList*; do
  NAME="${SOURCE:t}"
  TARGET="$TARGET_DIR/$NAME"
  if [[ "$SOURCE" == *.zsh ]]; then
    /usr/bin/install -m 700 "$SOURCE" "$TARGET"
  else
    /usr/bin/install -m 600 "$SOURCE" "$TARGET"
  fi
  /usr/bin/printf '%s\n' "$TARGET" >> "$MANIFEST"
done

/usr/bin/defaults write "$PREF_DOMAIN" enableSentry -bool false
/usr/bin/defaults write "$PREF_DOMAIN" honorGitignore -bool true
/usr/bin/defaults write "$PREF_DOMAIN" disableAutomaticVolumeIndexing -bool true
/usr/bin/defaults write "$PREF_DOMAIN" showActionRow -bool true
/usr/bin/defaults write "$PREF_DOMAIN" showFilePreview -bool true
/usr/bin/defaults write "$PREF_DOMAIN" showSearchHints -bool true

/usr/bin/printf 'customization_version=0.1.0\n' > "$ACTIVE_FILE"
/bin/chmod 600 "$ACTIVE_FILE"
/bin/rm -f "$INSTALLING_FILE"
/usr/bin/printf 'MacList customization installed. Restart Cling to load all scripts.\n'
