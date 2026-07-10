#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if (( $# != 1 )); then
  /usr/bin/printf 'Usage: %s /absolute/path/to/an/already-indexed-file\n' "${0:t}" >&2
  exit 2
fi
TARGET="$1"
RUNS="${MACLIST_BENCHMARK_RUNS:-20}"

run_with_timeout() {
  local SECONDS_LIMIT="$1"
  shift
  "$@" &
  local COMMAND_PID=$!
  (
    /bin/sleep "$SECONDS_LIMIT"
    /bin/kill -TERM "$COMMAND_PID" 2>/dev/null || true
    /bin/sleep 1
    /bin/kill -KILL "$COMMAND_PID" 2>/dev/null || true
  ) &
  local TIMER_PID=$!
  wait "$COMMAND_PID"
  local STATUS=$?
  /bin/kill "$TIMER_PID" 2>/dev/null || true
  wait "$TIMER_PID" 2>/dev/null || true
  return "$STATUS"
}

if [[ -d /Applications/Cling.app ]]; then
  APP=/Applications/Cling.app
elif [[ -d "$HOME/Applications/Cling.app" ]]; then
  APP="$HOME/Applications/Cling.app"
else
  /usr/bin/printf 'FAIL  Cling is not installed.\n' >&2
  exit 1
fi

[[ -f "$TARGET" || -d "$TARGET" ]] || {
  /usr/bin/printf 'FAIL  Target does not exist: %s\n' "$TARGET" >&2
  exit 1
}

CLI="$APP/Contents/SharedSupport/ClingCLI"
[[ -x "$CLI" ]] || {
  /usr/bin/printf 'FAIL  ClingCLI is missing.\n' >&2
  exit 1
}

if ! /usr/bin/pgrep -f "$APP/Contents/MacOS/Cling" >/dev/null; then
  /usr/bin/open "$APP"
  /bin/sleep 3
fi

STATUS_FILE="$(/usr/bin/mktemp -t maclist-status)"
if ! run_with_timeout 10 "$CLI" status --json > "$STATUS_FILE" 2>/dev/null; then
  /bin/rm -f "$STATUS_FILE"
  /usr/bin/printf 'FAIL  Cling status timed out while indexing; retry after background indexing settles.\n' >&2
  exit 1
fi
STATUS="$(< "$STATUS_FILE")"
/bin/rm -f "$STATUS_FILE"
INDEX_COUNT="$(/usr/bin/printf '%s' "$STATUS" | /usr/bin/plutil -extract indexCount raw -o - -)"
(( INDEX_COUNT > 0 )) || {
  /usr/bin/printf 'FAIL  Search index is empty.\n' >&2
  exit 1
}

QUERY="${TARGET:t:r}"
FOLDER="${TARGET:h}"
TIMINGS="$(/usr/bin/mktemp -t maclist-timings)"
RESULTS="$(/usr/bin/mktemp -t maclist-results)"
trap '/bin/rm -f "$TIMINGS" "$RESULTS"' EXIT

for (( RUN = 1; RUN <= RUNS; RUN++ )); do
  if ! run_with_timeout 10 "$CLI" search "$QUERY" --count 20 --folders "$FOLDER" --verbose > "$RESULTS" 2>> "$TIMINGS"; then
    /usr/bin/printf 'FAIL  Search timed out on run %s; retry after background indexing settles.\n' "$RUN" >&2
    exit 1
  fi
done

if ! /usr/bin/grep -F -i -- "$TARGET" "$RESULTS" >/dev/null; then
  /usr/bin/printf 'FAIL  Target was not returned by Cling search.\n' >&2
  exit 1
fi

SEARCH_P95="$(/usr/bin/perl -ne 'push @v, $1 if /search:\s+([0-9.]+)ms/; END { @v = sort { $a <=> $b } @v; $i = int(0.95 * @v + 0.999999) - 1; printf "%.1f", $v[$i] }' "$TIMINGS")"
ROUNDTRIP_P95="$(/usr/bin/perl -ne 'push @v, $1 if /roundtrip:\s+([0-9.]+)ms/; END { @v = sort { $a <=> $b } @v; $i = int(0.95 * @v + 0.999999) - 1; printf "%.1f", $v[$i] }' "$TIMINGS")"

/usr/bin/printf 'PASS  target found: %s\n' "$TARGET"
/usr/bin/printf 'PASS  indexed entries: %s\n' "$INDEX_COUNT"
/usr/bin/printf 'PASS  query P95: %sms; roundtrip P95: %sms across %s runs\n' "$SEARCH_P95" "$ROUNDTRIP_P95" "$RUNS"
