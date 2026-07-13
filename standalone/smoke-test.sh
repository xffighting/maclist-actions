#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

require_contains() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if ! grep -Eq "$pattern" "$file"; then
    print -u2 "FAIL $label"
    print -u2 -- '--- captured output ---'
    cat "$file" >&2
    exit 1
  fi
}

cd "$ROOT_DIR"

swiftc \
  -emit-library \
  -emit-module \
  -parse-as-library \
  -module-name MacListCore \
  Sources/MacListCore/*.swift \
  -o "$BUILD_DIR/libMacListCore.dylib" \
  -emit-module-path "$BUILD_DIR/MacListCore.swiftmodule"

swiftc \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lMacListCore \
  Sources/maclist/main.swift \
  -o "$BUILD_DIR/maclist"

mkdir -p "$BUILD_DIR/authorized/客户资料" "$BUILD_DIR/outside" "$BUILD_DIR/store"
chmod 750 "$BUILD_DIR/store"
print -n 'TOP_SECRET_DOCUMENT_BODY' > "$BUILD_DIR/authorized/客户资料/季度报价单.xlsx"
touch "$BUILD_DIR/authorized/Quarterly Plan.pdf"
touch "$BUILD_DIR/authorized/.hidden.txt"
touch "$BUILD_DIR/outside/outside.txt"
ln -s "$BUILD_DIR/outside/outside.txt" "$BUILD_DIR/authorized/outside-link.txt"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$BUILD_DIR/maclist" \
  index \
  --root "$BUILD_DIR/authorized" \
  --store "$BUILD_DIR/store/index.json" \
  --json > "$BUILD_DIR/index-output.json"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$BUILD_DIR/maclist" \
  search "报价" \
  --store "$BUILD_DIR/store/index.json" \
  --json > "$BUILD_DIR/chinese-search.json"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$BUILD_DIR/maclist" \
  search qtp \
  --store "$BUILD_DIR/store/index.json" > "$BUILD_DIR/fuzzy-search.txt"

doctor_status=0
DYLD_LIBRARY_PATH="$BUILD_DIR" "$BUILD_DIR/maclist" \
  doctor \
  --store "$BUILD_DIR/store/index.json" \
  --json > "$BUILD_DIR/doctor.json" || doctor_status=$?

if [[ "${MACLIST_SMOKE_DEBUG:-0}" == "1" ]]; then
  print -- '--- index command ---'
  cat "$BUILD_DIR/index-output.json"
  print -- '--- persisted index ---'
  cat "$BUILD_DIR/store/index.json"
  print -- '--- Chinese search ---'
  cat "$BUILD_DIR/chinese-search.json"
  print -- "--- doctor (exit $doctor_status) ---"
  cat "$BUILD_DIR/doctor.json"
fi

require_contains '"indexedFiles"' "$BUILD_DIR/index-output.json" 'index command did not return JSON'
require_contains '季度报价单\.xlsx' "$BUILD_DIR/chinese-search.json" 'short Chinese query did not return the expected file'
require_contains 'Quarterly Plan\.pdf' "$BUILD_DIR/fuzzy-search.txt" 'fuzzy subsequence query did not return the expected file'
require_contains 'Every indexed file remains inside an explicitly authorized root' "$BUILD_DIR/doctor.json" 'doctor did not report a healthy scope boundary'
[[ "$doctor_status" == "0" ]]

if grep -q 'TOP_SECRET_DOCUMENT_BODY' "$BUILD_DIR/store/index.json"; then
  print -u2 'FAIL index contains document body'
  exit 1
fi
if grep -q '.hidden.txt\|outside-link.txt\|outside.txt' "$BUILD_DIR/store/index.json"; then
  print -u2 'FAIL index escaped the authorized visible regular-file scope'
  exit 1
fi

[[ "$(stat -f '%Lp' "$BUILD_DIR/store")" == "750" ]]
[[ "$(stat -f '%Lp' "$BUILD_DIR/store/index.json")" == "600" ]]

print 'PASS standalone library and CLI compile without Cling'
print 'PASS explicit-root indexing excludes hidden files and symbolic links'
print 'PASS custom store permissions are preserved and index file is private (0600)'
print 'PASS Chinese short query and fuzzy subsequence query'
print 'PASS doctor reports a healthy index'
