#!/bin/zsh
set -euo pipefail

TARGET_DIR="${MACLIST_TARGET_DIR:-$HOME/Library/Application Scripts/Cling}"
STATE_DIR="${MACLIST_STATE_DIR:-$HOME/Library/Application Support/MacList Custom}"
PREF_DOMAIN="${MACLIST_PREF_DOMAIN:-com.lowtechguys.Cling}"
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
LEGACY_STATE=0

die() {
  /usr/bin/printf 'MacList uninstall stopped: %s\n' "$1" >&2
  exit 1
}

if [[ ! -f "$FILES_BEFORE" &&
      ! -f "$PREFS_BEFORE" &&
      ! -f "$MANIFEST" &&
      ! -f "$ACTIVE_FILE" &&
      ! -f "$INSTALLING_FILE" &&
      ! -f "$TARGET_DIR_BEFORE" ]]; then
  /usr/bin/printf 'No MacList customization state found. Nothing was changed.\n'
  exit 0
fi

if [[ -f "$FILES_BEFORE" ]]; then
  while IFS=$'\t' read -r NAME STATE; do
    [[ -n "$NAME" && "$NAME" == MacList* && "$NAME" != */* ]] || die "invalid file snapshot entry"
    TARGET="$TARGET_DIR/$NAME"
    if [[ "$STATE" == present ]]; then
      [[ -e "$BACKUP_DIR/$NAME" ]] || die "backup missing for $NAME"
      /usr/bin/ditto "$BACKUP_DIR/$NAME" "$TARGET"
    elif [[ "$STATE" == absent ]]; then
      /bin/rm -f "$TARGET"
    else
      die "invalid file snapshot state for $NAME"
    fi
  done < "$FILES_BEFORE"
elif [[ -f "$MANIFEST" ]]; then
  LEGACY_STATE=1
  while IFS= read -r FILE; do
    [[ "$FILE" == "$TARGET_DIR"/MacList* ]] && /bin/rm -f "$FILE"
  done < "$MANIFEST"
fi

if [[ -f "$PREFS_BEFORE" ]]; then
  while IFS=$'\t' read -r KEY STATE VALUE; do
    [[ "${PREF_KEYS[(Ie)$KEY]}" -gt 0 ]] || die "invalid preference snapshot entry"
    if [[ "$STATE" == present ]]; then
      [[ "$VALUE" == 0 || "$VALUE" == 1 ]] || die "invalid Boolean snapshot for $KEY"
      BOOL=false
      [[ "$VALUE" == 1 ]] && BOOL=true
      /usr/bin/defaults write "$PREF_DOMAIN" "$KEY" -bool "$BOOL"
    elif [[ "$STATE" == absent ]]; then
      /usr/bin/defaults delete "$PREF_DOMAIN" "$KEY" 2>/dev/null || true
    else
      die "invalid preference snapshot state for $KEY"
    fi
  done < "$PREFS_BEFORE"
elif (( LEGACY_STATE )); then
  for KEY in "${PREF_KEYS[@]}"; do
    /usr/bin/defaults delete "$PREF_DOMAIN" "$KEY" 2>/dev/null || true
  done
else
  die "preference snapshot is missing; Cling preferences were left unchanged"
fi

if [[ -f "$TARGET_DIR_BEFORE" ]]; then
  IFS=$'\t' read -r TARGET_STATE TARGET_MODE < "$TARGET_DIR_BEFORE"
  if [[ "$TARGET_STATE" == present ]]; then
    [[ -d "$TARGET_DIR" && "$TARGET_MODE" == <-> ]] || die "invalid target directory snapshot"
    /bin/chmod "$TARGET_MODE" "$TARGET_DIR"
  elif [[ "$TARGET_STATE" == absent ]]; then
    /bin/rmdir "$TARGET_DIR" 2>/dev/null || true
  else
    die "invalid target directory snapshot state"
  fi
fi

/bin/rm -f "$MANIFEST" "$ACTIVE_FILE" "$INSTALLING_FILE" "$FILES_BEFORE" "$PREFS_BEFORE" "$TARGET_DIR_BEFORE"
/bin/rm -rf "$BACKUP_DIR"
/bin/rmdir "$STATE_DIR" 2>/dev/null || true
/usr/bin/printf 'MacList customization removed. Original scripts and preferences were restored; Cling and its index remain.\n'
