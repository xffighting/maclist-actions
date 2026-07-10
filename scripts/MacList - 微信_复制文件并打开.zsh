#!/bin/zsh
# filesOnly: true
# minFiles: 1
# description: 复制真实文件并打开微信；选择聊天后按 Command+V，不会自动发送
# key: w
# icon: bubble.left.and.bubble.right

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
COUNT="$(/usr/bin/osascript -l JavaScript "$SCRIPT_DIR/MacList-prepare-share.jxa" "$@")"

if ! /usr/bin/open -a WeChat; then
  /usr/bin/osascript -e 'display notification "文件已复制，但没有找到微信" with title "MacList"'
  exit 1
fi

/usr/bin/osascript -e "display notification \"已复制 ${COUNT} 个文件；选择聊天后按 Command+V\" with title \"MacList · 微信\""
