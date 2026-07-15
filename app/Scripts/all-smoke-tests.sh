#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/Scripts/smoke-test.sh"
"$ROOT/Scripts/root-policy-smoke.sh"
"$ROOT/Scripts/local-index-service-smoke.sh"
"$ROOT/Scripts/local-index-menu-smoke.sh"
