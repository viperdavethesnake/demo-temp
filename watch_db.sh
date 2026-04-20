#!/bin/bash
# Poll ClickHouse every 5s, print scan_results growth.
CH="http://localhost:8123/?user=symphony&password=symphony"
while true; do
  ts=$(date +%H:%M:%S)
  tables=$(curl -s "$CH" --data "SELECT name FROM system.tables WHERE database='symphony' FORMAT TSV" 2>/dev/null)
  if [ -z "$tables" ]; then
    echo "$ts | no tables in symphony db yet"
  else
    for t in $tables; do
      stats=$(curl -s "$CH" --data "SELECT count() AS rows, countDistinct(run_id) AS runs, toString(max(modified)) AS newest_modified, formatReadableSize(sum(size)) AS total_bytes FROM symphony.$t FORMAT TSV" 2>/dev/null)
      echo "$ts | $t | $stats"
    done
  fi
  sleep 5
done
