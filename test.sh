#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${ROOT:h}"
HELPER="$ROOT/scripts/MacList-prepare-share.jxa"
if [[ -f "$ROOT/README.md" ]]; then
  TEST_FILE="$ROOT/README.md"
else
  TEST_FILE="$REPO_ROOT/README.md"
fi
FAILURES=0
TMP_ROOT="$(/usr/bin/mktemp -d -t maclist-custom-test)"
PREF_DOMAIN="com.maclist.custom.test.$$"
TEST_TARGET="$TMP_ROOT/scripts"
TEST_STATE="$TMP_ROOT/state"

cleanup() {
  /usr/bin/defaults delete "$PREF_DOMAIN" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() { /usr/bin/printf 'PASS  %s\n' "$1" }
fail() { /usr/bin/printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

for SCRIPT in "$ROOT"/*.sh "$ROOT"/scripts/*.zsh; do
  if /bin/zsh -n "$SCRIPT"; then
    pass "syntax ${SCRIPT:t}"
  else
    fail "syntax ${SCRIPT:t}"
  fi
done

for SCRIPT in "$ROOT"/scripts/*.zsh; do
  if /usr/bin/grep -q '^# description:' "$SCRIPT" &&
     /usr/bin/grep -q '^# key:' "$SCRIPT" &&
     /usr/bin/grep -q '^# icon:' "$SCRIPT"; then
    pass "metadata ${SCRIPT:t}"
  else
    fail "metadata ${SCRIPT:t}"
  fi
done

KEY_COUNT="$(/usr/bin/grep -h '^# key:' "$ROOT"/scripts/*.zsh | /usr/bin/awk '{print $3}' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
UNIQUE_KEY_COUNT="$(/usr/bin/grep -h '^# key:' "$ROOT"/scripts/*.zsh | /usr/bin/awk '{print $3}' | /usr/bin/sort -u | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
if [[ "$KEY_COUNT" == "$UNIQUE_KEY_COUNT" ]] &&
   /usr/bin/grep -q '^# key: m$' "$ROOT/scripts/MacList - Apple Mail_复制文件并打开.zsh" &&
   /usr/bin/grep -q '^# key: o$' "$ROOT/scripts/MacList - Outlook_复制文件并打开.zsh"; then
  pass "action shortcuts are unique and mail shortcuts are registered"
else
  fail "action shortcuts are unique and mail shortcuts are registered"
fi

if /usr/bin/grep -Fq 'MacList-prepare-share.jxa' "$ROOT/scripts/MacList - Apple Mail_复制文件并打开.zsh" &&
   /usr/bin/grep -Fq '/usr/bin/open -b com.apple.mail' "$ROOT/scripts/MacList - Apple Mail_复制文件并打开.zsh" &&
   /usr/bin/grep -Fq 'MacList-prepare-share.jxa' "$ROOT/scripts/MacList - Outlook_复制文件并打开.zsh" &&
   /usr/bin/grep -Fq '/usr/bin/open -b com.microsoft.Outlook' "$ROOT/scripts/MacList - Outlook_复制文件并打开.zsh" &&
   ! /usr/bin/grep -Eiq 'System Events|keystroke|key code|mailto:|tell application|recipient|compose|paste|send' \
     "$ROOT/scripts/MacList - Apple Mail_复制文件并打开.zsh" \
     "$ROOT/scripts/MacList - Outlook_复制文件并打开.zsh"; then
  pass "mail actions only copy file URLs and open their applications"
else
  fail "mail actions only copy file URLs and open their applications"
fi

if [[ "${MACLIST_TEST_NO_UI:-0}" == 1 ]]; then
  pass "UI clipboard checks skipped by explicit CI mode"
else
  COUNT="$(/usr/bin/osascript -l JavaScript "$HELPER" "$TEST_FILE")"
  if [[ "$COUNT" == 1 ]]; then
    pass "pasteboard helper accepted one file"
  else
    fail "pasteboard helper accepted one file"
  fi

  TYPES="$(/usr/bin/osascript -l JavaScript -e 'function run(){ObjC.import("AppKit"); return ObjC.deepUnwrap($.NSPasteboard.generalPasteboard.types).join("\n")}')"
  if [[ "$TYPES" == *"public.file-url"* && "$TYPES" == *"NSFilenamesPboardType"* ]]; then
    pass "pasteboard exposes real file URL types"
  else
    fail "pasteboard exposes real file URL types"
  fi

  "$ROOT/scripts/MacList - 复制资料清单.zsh" "$TEST_FILE"
  TEXT="$(/usr/bin/pbpaste)"
  if [[ "$TEXT" == *"README.md"* && "$TEXT" == *"$TEST_FILE"* ]]; then
    pass "text checklist contains filename and path"
  else
    fail "text checklist contains filename and path"
  fi
fi

if ! /usr/bin/grep -E -q '(^|[ /])(curl|wget|nc)([ /]|$)' "$ROOT"/scripts/*; then
  pass "custom scripts contain no network client"
else
  fail "custom scripts contain no network client"
fi

/bin/mkdir -p "$TEST_TARGET"
/bin/chmod 755 "$TEST_TARGET"
ORIGINAL="$TEST_TARGET/MacList - 微信_复制文件并打开.zsh"
/usr/bin/printf '#!/bin/zsh\n# original local workflow\n' > "$ORIGINAL"
/bin/chmod 700 "$ORIGINAL"
ORIGINAL_HASH="$(/usr/bin/shasum -a 256 "$ORIGINAL" | /usr/bin/awk '{print $1}')"
/usr/bin/defaults write "$PREF_DOMAIN" honorGitignore -bool false
/usr/bin/defaults write "$PREF_DOMAIN" showSearchHints -bool true

EMPTY_TARGET="$TMP_ROOT/empty-scripts"
EMPTY_STATE="$TMP_ROOT/empty-state"
/bin/mkdir -p "$EMPTY_TARGET"
MACLIST_TARGET_DIR="$EMPTY_TARGET" \
MACLIST_STATE_DIR="$EMPTY_STATE" \
MACLIST_PREF_DOMAIN="$PREF_DOMAIN" \
  "$ROOT/uninstall.sh" >/dev/null
if [[ "$(/usr/bin/defaults read "$PREF_DOMAIN" honorGitignore 2>/dev/null)" == 0 &&
      "$(/usr/bin/defaults read "$PREF_DOMAIN" showSearchHints 2>/dev/null)" == 1 &&
      ! -e "$EMPTY_STATE" ]]; then
  pass "uninstall without state changes nothing"
else
  fail "uninstall without state changes nothing"
fi

MACLIST_SKIP_APP_CHECK=1 \
MACLIST_TARGET_DIR="$TEST_TARGET" \
MACLIST_STATE_DIR="$TEST_STATE" \
MACLIST_PREF_DOMAIN="$PREF_DOMAIN" \
  "$ROOT/install.sh" >/dev/null

if [[ "$(/usr/bin/stat -f %Lp "$TEST_TARGET")" == 700 ]]; then
  pass "install protects the scripts directory"
else
  fail "install protects the scripts directory"
fi

if /usr/bin/cmp -s "$ROOT/scripts/MacList - 微信_复制文件并打开.zsh" "$ORIGINAL"; then
  pass "sandbox install replaced the workflow"
else
  fail "sandbox install replaced the workflow"
fi

if [[ -x "$TEST_TARGET/MacList - Apple Mail_复制文件并打开.zsh" &&
      -x "$TEST_TARGET/MacList - Outlook_复制文件并打开.zsh" ]]; then
  pass "sandbox install added Apple Mail and Outlook workflows"
else
  fail "sandbox install added Apple Mail and Outlook workflows"
fi

if /usr/bin/grep -Fqx 'customization_version=0.2.0' "$TEST_STATE/active"; then
  pass "install state records the v0.2.0 customization version"
else
  fail "install state records the v0.2.0 customization version"
fi

# Emulate an active pre-mail-actions installation, then verify an in-place
# upgrade records the new files as originally absent for safe rollback.
/usr/bin/awk -F '\t' '$1 != "MacList - Apple Mail_复制文件并打开.zsh" && $1 != "MacList - Outlook_复制文件并打开.zsh"' \
  "$TEST_STATE/files.before.tsv" > "$TEST_STATE/files.before.next.tsv"
/bin/mv "$TEST_STATE/files.before.next.tsv" "$TEST_STATE/files.before.tsv"
/bin/chmod 600 "$TEST_STATE/files.before.tsv"
/bin/rm -f \
  "$TEST_TARGET/MacList - Apple Mail_复制文件并打开.zsh" \
  "$TEST_TARGET/MacList - Outlook_复制文件并打开.zsh"

MACLIST_SKIP_APP_CHECK=1 \
MACLIST_TARGET_DIR="$TEST_TARGET" \
MACLIST_STATE_DIR="$TEST_STATE" \
MACLIST_PREF_DOMAIN="$PREF_DOMAIN" \
  "$ROOT/install.sh" >/dev/null

if /usr/bin/grep -Fqx $'MacList - Apple Mail_复制文件并打开.zsh\tabsent' "$TEST_STATE/files.before.tsv" &&
   /usr/bin/grep -Fqx $'MacList - Outlook_复制文件并打开.zsh\tabsent' "$TEST_STATE/files.before.tsv"; then
  pass "active upgrade extends the rollback snapshot for new workflows"
else
  fail "active upgrade extends the rollback snapshot for new workflows"
fi

MACLIST_SKIP_APP_CHECK=1 \
MACLIST_TARGET_DIR="$TEST_TARGET" \
MACLIST_STATE_DIR="$TEST_STATE" \
MACLIST_PREF_DOMAIN="$PREF_DOMAIN" \
  "$ROOT/install.sh" >/dev/null
pass "sandbox reinstall is idempotent"

/usr/bin/printf '# edited after install\n' >> "$ORIGINAL"
if MACLIST_SKIP_APP_CHECK=1 \
   MACLIST_TARGET_DIR="$TEST_TARGET" \
   MACLIST_STATE_DIR="$TEST_STATE" \
   MACLIST_PREF_DOMAIN="$PREF_DOMAIN" \
     "$ROOT/install.sh" >/dev/null 2>&1; then
  fail "post-install edits stop overwrite"
else
  pass "post-install edits stop overwrite"
fi

# Emulate the manifest shape produced by the previous installer during an
# active upgrade: new files were listed in the manifest but not the snapshot.
/usr/bin/awk -F '\t' '$1 != "MacList - Apple Mail_复制文件并打开.zsh" && $1 != "MacList - Outlook_复制文件并打开.zsh"' \
  "$TEST_STATE/files.before.tsv" > "$TEST_STATE/files.before.next.tsv"
/bin/mv "$TEST_STATE/files.before.next.tsv" "$TEST_STATE/files.before.tsv"
/bin/chmod 600 "$TEST_STATE/files.before.tsv"

MACLIST_TARGET_DIR="$TEST_TARGET" \
MACLIST_STATE_DIR="$TEST_STATE" \
MACLIST_PREF_DOMAIN="$PREF_DOMAIN" \
  "$ROOT/uninstall.sh" >/dev/null

RESTORED_HASH="$(/usr/bin/shasum -a 256 "$ORIGINAL" | /usr/bin/awk '{print $1}')"
if [[ "$RESTORED_HASH" == "$ORIGINAL_HASH" ]]; then
  pass "uninstall restored the original workflow"
else
  fail "uninstall restored the original workflow"
fi

if [[ ! -e "$TEST_TARGET/MacList - 钉钉_复制文件并打开.zsh" ]]; then
  pass "uninstall removed newly added workflows"
else
  fail "uninstall removed newly added workflows"
fi


if [[ ! -e "$TEST_TARGET/MacList - Apple Mail_复制文件并打开.zsh" &&
      ! -e "$TEST_TARGET/MacList - Outlook_复制文件并打开.zsh" ]]; then
  pass "uninstall removes workflows recorded only by a legacy upgrade manifest"
else
  fail "uninstall removes workflows recorded only by a legacy upgrade manifest"
fi

if [[ "$(/usr/bin/defaults read "$PREF_DOMAIN" honorGitignore 2>/dev/null)" == 0 &&
      "$(/usr/bin/defaults read "$PREF_DOMAIN" showSearchHints 2>/dev/null)" == 1 ]] &&
   ! /usr/bin/defaults read "$PREF_DOMAIN" enableSentry >/dev/null 2>&1; then
  pass "uninstall restored original preference state"
else
  fail "uninstall restored original preference state"
fi

if [[ ! -e "$TEST_STATE" ]]; then
  pass "uninstall removed private state after restore"
else
  fail "uninstall removed private state after restore"
fi

if [[ "$(/usr/bin/stat -f %Lp "$TEST_TARGET")" == 755 ]]; then
  pass "uninstall restored the scripts directory mode"
else
  fail "uninstall restored the scripts directory mode"
fi

if (( FAILURES > 0 )); then
  /usr/bin/printf '%d test(s) failed.\n' "$FAILURES"
  exit 1
fi

/usr/bin/printf 'All customization tests passed.\n'
