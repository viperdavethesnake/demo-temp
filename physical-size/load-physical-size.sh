#!/usr/bin/env bash
# Driver for probe-physical-size.ps1.
# Runs pre-flight checks, streams file list from ClickHouse into the walker,
# then prints validation numbers.
#
# Usage:  ./load-physical-size.sh [run_id]
# Default run_id is the current lab's active run.

set -euo pipefail

RUN_ID="${1:-c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233}"
CH_URL="${CH_URL:-http://localhost:8123}"
CH_USER="${CH_USER:-symphony}"
CH_PASS="${CH_PASS:-symphony}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALKER="$SCRIPT_DIR/probe-physical-size.ps1"

ch_query() {
  curl -sf -u "$CH_USER:$CH_PASS" "$CH_URL/" --data-binary "$1"
}

echo "== pre-flight =="

if ! wsl -l -v 2>&1 | tr -d '\r\0' | grep -q "Running"; then
  echo "ERROR: WSL is not Running. Start the keepalive (see RESUME.md) before walking." >&2
  exit 1
fi
echo "  wsl:        Running"

if ! curl -sf "$CH_URL/ping" >/dev/null; then
  echo "ERROR: ClickHouse unreachable at $CH_URL/ping" >&2
  exit 1
fi
echo "  clickhouse: reachable at $CH_URL"

TABLE_EXISTS=$(ch_query "SELECT count() FROM system.tables WHERE database='symphony' AND name='file_physical'")
if [ "$TABLE_EXISTS" != "1" ]; then
  echo "ERROR: symphony.file_physical missing. Apply schema.sql first:" >&2
  echo "  curl -u $CH_USER:$CH_PASS $CH_URL/ --data-binary @$SCRIPT_DIR/schema.sql" >&2
  exit 1
fi
echo "  table:      symphony.file_physical exists"

if [ ! -f "$WALKER" ]; then
  echo "ERROR: walker not found at $WALKER" >&2
  exit 1
fi

EXPECTED=$(ch_query "SELECT count() FROM symphony.scan_results WHERE run_id='$RUN_ID' AND filename != ''")
if [ -z "$EXPECTED" ] || [ "$EXPECTED" = "0" ]; then
  echo "ERROR: no scan_results rows for run_id=$RUN_ID" >&2
  exit 1
fi
EXISTING=$(ch_query "SELECT count() FROM symphony.file_physical WHERE run_id='$RUN_ID'")
echo "  run_id:     $RUN_ID"
echo "  expected:   $EXPECTED files to probe"
echo "  existing:   $EXISTING rows already in file_physical for this run"
if [ "$EXISTING" -gt "0" ]; then
  echo "  note:       re-probe will insert fresh rows; ReplacingMergeTree dedupes on merge"
fi

echo ""
echo "== walking =="
START=$(date +%s)

ch_query "SELECT run_id, file_uri FROM symphony.scan_results WHERE run_id='$RUN_ID' AND filename != '' FORMAT TabSeparated" \
  | pwsh -NoProfile -File "$WALKER" -RunId "$RUN_ID"

END=$(date +%s)
ELAPSED=$((END - START))

echo ""
echo "== validation =="
PROBED=$(ch_query "SELECT uniqExact(file_uri) FROM symphony.file_physical WHERE run_id='$RUN_ID'")
PHYSICAL_TOTAL=$(ch_query "SELECT formatReadableSize(sum(allocated)) FROM symphony.file_physical WHERE run_id='$RUN_ID'")
MISSING=$((EXPECTED - PROBED))
LOGICAL_TOTAL=$(ch_query "SELECT formatReadableSize(sum(size)) FROM symphony.scan_results WHERE run_id='$RUN_ID' AND filename!=''")

printf "  expected:    %s\n" "$EXPECTED"
printf "  probed:      %s\n" "$PROBED"
printf "  missing:     %s\n" "$MISSING"
printf "  logical:     %s\n" "$LOGICAL_TOTAL"
printf "  physical:    %s\n" "$PHYSICAL_TOTAL"
printf "  elapsed:     %ss\n" "$ELAPSED"
