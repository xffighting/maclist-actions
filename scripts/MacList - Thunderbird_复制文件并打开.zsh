#!/bin/zsh
# filesOnly: true
# minFiles: 1
# description: 复制真实文件并打开 Thunderbird；新建邮件后按 Command+V，不会自动发送
# key: e
# icon: envelope

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
COUNT="$(/usr/bin/osascript -l JavaScript "$SCRIPT_DIR/MacList-prepare-share.jxa" "$@")"

if ! /usr/bin/open -a Thunderbird; then
  /usr/bin/osascript -e 'display notification "文件已复制，但没有找到 Thunderbird" with title "MacList"'
  exit 1
fi

/usr/bin/osascript -e "display notification \"已复制 ${COUNT} 个文件；新建邮件后按 Command+V\" with title \"MacList · 邮件\""
