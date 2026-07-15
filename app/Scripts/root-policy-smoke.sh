#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/maclist-root-policy-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT"/Sources/MacListCore/*.swift \
  "$ROOT/SmokeTests/LocalIndexRootPolicySmoke.swift" \
  -o "$BUILD_DIR/local-index-root-policy-smoke"

"$BUILD_DIR/local-index-root-policy-smoke"
