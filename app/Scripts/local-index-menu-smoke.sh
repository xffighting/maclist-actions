#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/maclist-local-index-menu-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT"/Sources/MacListCore/*.swift \
  "$ROOT"/SmokeTests/LocalIndexMenuPresentationSmoke.swift \
  -o "$BUILD_DIR/local-index-menu-smoke"

"$BUILD_DIR/local-index-menu-smoke"
