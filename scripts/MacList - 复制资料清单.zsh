#!/bin/zsh
# minFiles: 1
# description: 复制文件名和完整路径清单，适合先发文字说明
# key: l
# icon: list.bullet.clipboard

set -euo pipefail

TMP="$(/usr/bin/mktemp -t maclist-files)"
trap '/bin/rm -f "$TMP"' EXIT

for PATH_ITEM in "$@"; do
  NAME="${PATH_ITEM:t}"
  /usr/bin/printf '• %s\n  %s\n' "$NAME" "$PATH_ITEM" >> "$TMP"
done

/usr/bin/pbcopy < "$TMP"
/usr/bin/osascript -e "display notification \"已复制 $# 项资料清单\" with title \"MacList\""
