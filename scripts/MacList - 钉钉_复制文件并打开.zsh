#!/bin/zsh
# filesOnly: true
# minFiles: 1
# description: 复制真实文件并打开钉钉；选择聊天后按 Command+V，不会自动发送
# key: d
# icon: paperplane

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
COUNT="$(/usr/bin/osascript -l JavaScript "$SCRIPT_DIR/MacList-prepare-share.jxa" "$@")"

if ! /usr/bin/open -a DingTalk; then
  /usr/bin/osascript -e 'display notification "文件已复制，但没有找到钉钉" with title "MacList"'
  exit 1
fi

/usr/bin/osascript -e "display notification \"已复制 ${COUNT} 个文件；选择聊天后按 Command+V\" with title \"MacList · 钉钉\""
