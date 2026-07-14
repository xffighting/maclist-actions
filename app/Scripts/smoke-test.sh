#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/maclist-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT/Sources/MacListCore/DialogSelectionPolicy.swift" \
  "$ROOT/Sources/MacListCore/Models.swift" \
  "$ROOT/Sources/MacListCore/SearchEngine.swift" \
  "$ROOT/Sources/MacListCore/DialogObservation.swift" \
  "$ROOT/SmokeTests/FuzzySearchSmoke.swift" \
  "$ROOT/SmokeTests/DialogObservationSmoke.swift" \
  "$ROOT/SmokeTests/DialogSelectionPolicySmoke.swift" \
  -o "$BUILD_DIR/dialog-selection-policy-smoke"

"$BUILD_DIR/dialog-selection-policy-smoke"
