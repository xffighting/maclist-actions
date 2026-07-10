#!/bin/zsh
set -euo pipefail

TARGET_DIR="${MACLIST_TARGET_DIR:-$HOME/Library/Application Scripts/Cling}"
STATE_DIR="${MACLIST_STATE_DIR:-$HOME/Library/Application Support/MacList Custom}"
PREF_DOMAIN="${MACLIST_PREF_DOMAIN:-com.lowtechguys.Cling}"
EXPECTED_VERSION="2.6.5"
EXPECTED_BUNDLE_ID="com.lowtechguys.Cling"
EXPECTED_TEAM_ID="RDDXV84A73"
FAILURES=0

find_app() {
  if [[ -n "${MACLIST_APP_PATH:-}" && -d "${MACLIST_APP_PATH:-}" ]]; then
    /usr/bin/printf '%s\n' "${MACLIST_APP_PATH:-}"
  elif [[ -d /Applications/Cling.app ]]; then
    /usr/bin/printf '%s\n' /Applications/Cling.app
  elif [[ -d "$HOME/Applications/Cling.app" ]]; then
    /usr/bin/printf '%s\n' "$HOME/Applications/Cling.app"
  fi
}

APP="$(find_app)"

check() {
  local LABEL="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    /usr/bin/printf 'PASS  %s\n' "$LABEL"
  else
    /usr/bin/printf 'FAIL  %s\n' "$LABEL"
    FAILURES=$((FAILURES + 1))
  fi
}

check_optional() {
  local LABEL="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    /usr/bin/printf 'PASS  %s\n' "$LABEL"
  else
    /usr/bin/printf 'WARN  %s (optional action unavailable)\n' "$LABEL"
  fi
}

app_version_ok() {
  [[ -n "$APP" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)" == "$EXPECTED_VERSION" ]]
}

app_identity_ok() {
  local BUNDLE_ID TEAM_ID
  [[ -n "$APP" ]] || return 1
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)"
  TEAM_ID="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  [[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" && "$TEAM_ID" == "$EXPECTED_TEAM_ID" ]]
}

cli_index_ready() {
  local STATUS COUNT
  [[ -x "$APP/Contents/SharedSupport/ClingCLI" ]] || return 1
  STATUS="$("$APP/Contents/SharedSupport/ClingCLI" status --json 2>/dev/null)" || return 1
  COUNT="$(/usr/bin/printf '%s' "$STATUS" | /usr/bin/plutil -extract indexCount raw -o - - 2>/dev/null)" || return 1
  (( COUNT > 0 ))
}

check "Cling app installed" /bin/test -d "$APP"
check "Cling version is $EXPECTED_VERSION" app_version_ok
check "Official bundle and signing team" app_identity_ok
check "Developer ID signature valid" /usr/bin/codesign --verify --deep --strict "$APP"
check "Cling is running" /usr/bin/pgrep -f "$APP/Contents/MacOS/Cling"
check "First-run setup completed" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" onboardingCompleted 2>/dev/null)" == 1 ]]' -- "$PREF_DOMAIN"
check "Search index responds" cli_index_ready
check "Custom scripts directory private" /bin/zsh -c '[[ "$(/usr/bin/stat -f %Lp "$1")" == 700 ]]' -- "$TARGET_DIR"
check "Customization state private" /bin/zsh -c '[[ "$(/usr/bin/stat -f %Lp "$1")" == 700 ]]' -- "$STATE_DIR"
check "Install manifest private" /bin/zsh -c '[[ "$(/usr/bin/stat -f %Lp "$1/installed-files.txt")" == 600 ]]' -- "$STATE_DIR"
check "WeChat workflow installed" /bin/test -x "$TARGET_DIR/MacList - 微信_复制文件并打开.zsh"
check "DingTalk workflow installed" /bin/test -x "$TARGET_DIR/MacList - 钉钉_复制文件并打开.zsh"
check "Thunderbird workflow installed" /bin/test -x "$TARGET_DIR/MacList - Thunderbird_复制文件并打开.zsh"
check "Checklist workflow installed" /bin/test -x "$TARGET_DIR/MacList - 复制资料清单.zsh"
check "File URL helper installed" /bin/test -f "$TARGET_DIR/MacList-prepare-share.jxa"
check "Sentry disabled" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" enableSentry 2>/dev/null)" == 0 ]]' -- "$PREF_DOMAIN"
check "Git ignore respected" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" honorGitignore 2>/dev/null)" == 1 ]]' -- "$PREF_DOMAIN"
check "External volumes require opt-in" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" disableAutomaticVolumeIndexing 2>/dev/null)" == 1 ]]' -- "$PREF_DOMAIN"
check "Action row visible" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" showActionRow 2>/dev/null)" == 1 ]]' -- "$PREF_DOMAIN"
check "File preview visible" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" showFilePreview 2>/dev/null)" == 1 ]]' -- "$PREF_DOMAIN"
check "Search hints visible" /bin/zsh -c '[[ "$(/usr/bin/defaults read "$1" showSearchHints 2>/dev/null)" == 1 ]]' -- "$PREF_DOMAIN"
check "Cling index directory private" /bin/zsh -c '[[ ! -e "$1" || "$(/usr/bin/stat -f %Lp "$1")" == 700 ]]' -- "$HOME/Library/Caches/com.lowtechguys.Cling"
check_optional "WeChat available" /usr/bin/open -Ra WeChat
check_optional "DingTalk available" /usr/bin/open -Ra DingTalk
check_optional "Thunderbird available" /usr/bin/open -Ra Thunderbird

if (( FAILURES > 0 )); then
  /usr/bin/printf '%d check(s) failed.\n' "$FAILURES"
  exit 1
fi

/usr/bin/printf 'MacList customization is healthy.\n'
