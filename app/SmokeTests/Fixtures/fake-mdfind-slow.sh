#!/bin/zsh
set -euo pipefail

home_directory="$3"
printf '%s\0' "$home_directory/Documents/第一份报价.pdf"
exec /bin/sleep 5
