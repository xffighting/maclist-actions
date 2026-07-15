#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/maclist-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT"/Sources/MacListCore/*.swift \
  "$ROOT/SmokeTests/FuzzySearchSmoke.swift" \
  "$ROOT/SmokeTests/SpotlightProviderSmoke.swift" \
  "$ROOT/SmokeTests/DialogObservationSmoke.swift" \
  "$ROOT/SmokeTests/AuthorizedFolderBookmarkSmoke.swift" \
  "$ROOT/SmokeTests/LocalIndexSmoke.swift" \
  "$ROOT/SmokeTests/SearchResultSetSmoke.swift" \
  "$ROOT/SmokeTests/SearchEpochSmoke.swift" \
  "$ROOT/SmokeTests/DialogSelectionPolicySmoke.swift" \
  -o "$BUILD_DIR/dialog-selection-policy-smoke"

"$BUILD_DIR/dialog-selection-policy-smoke"
