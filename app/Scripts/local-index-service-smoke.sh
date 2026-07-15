#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/maclist-local-index-service-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT"/Sources/MacListCore/*.swift \
  "$ROOT"/SmokeTests/LocalIndexServiceSmoke.swift \
  -o "$BUILD_DIR/local-index-service-smoke"

"$BUILD_DIR/local-index-service-smoke"
