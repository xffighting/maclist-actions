#!/bin/zsh
set -euo pipefail

home_directory="$3"
printf '%s\0' "$home_directory/Documents/客户报价单.xlsx"
printf '%s\0' "$home_directory/Library/Mobile Documents/com~apple~CloudDocs/资料/云端报价.pdf"
printf '%s\0' "$home_directory/Library/CloudStorage/OneDrive/Documents/年度报价.xlsx"
printf '%s\0' "$home_directory/.Trash/不应出现.pdf"
