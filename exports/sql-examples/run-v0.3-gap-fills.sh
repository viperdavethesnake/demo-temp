#!/bin/bash
set -uo pipefail

CH='http://localhost:8123/?user=symphony&password=symphony&default_format=CSVWithNames'
OUT='/mnt/c/Users/Administrator/Documents/claude/symphony/exports/source-data/v0.3-gap-fills'
mkdir -p "$OUT"

ERRORS=""
run() {
    local n="$1" file="$2" sql="$3"
    echo "--- Query $n -> $file ---"
    local resp http
    resp=$(curl -sS -w '\n%{http_code}' "$CH" --data-binary "$sql")
    http=$(printf '%s' "$resp" | tail -n1)
    body=$(printf '%s' "$resp" | sed '$d')
    if [ "$http" = "200" ]; then
        printf '%s' "$body" > "$OUT/$file"
        echo "OK ($(wc -l < "$OUT/$file") lines)"
    else
        echo "FAIL http=$http"
        echo "$body" | head -20
        ERRORS="${ERRORS}Query ${n} (${file}) — HTTP ${http}:\n${body}\n\n"
    fi
}

run 1 age-bands-last-accessed.csv "SELECT
    multiIf(
        last_accessed > now() - INTERVAL 90 DAY,  '1_Active_lt90d',
        last_accessed > now() - INTERVAL 1 YEAR,  '2_Warm_90d-1y',
        last_accessed > now() - INTERVAL 3 YEAR,  '3_Cold_1-3y',
                                                  '4_Frozen_3yplus'
    )                                                              AS band,
    count()                                                        AS files,
    sum(size)                                                      AS bytes,
    formatReadableSize(sum(size))                                  AS bytes_human,
    round(100.0 * count() / sum(count()) OVER (), 2)               AS pct_files,
    round(100.0 * sum(size) / sum(sum(size)) OVER (), 2)           AS pct_bytes
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'
GROUP BY band
ORDER BY band"

run 2 top-dirs-broken-inheritance.csv "SELECT
    arrayStringConcat(arraySlice(splitByChar('/', file_path), 1, 6), '/')  AS directory,
    count()                                                                AS broken_files,
    sum(size)                                                              AS broken_bytes,
    formatReadableSize(sum(size))                                          AS broken_human
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'
  AND positionCaseInsensitive(acl_analysis, 'B') > 0
GROUP BY directory
HAVING broken_files > 1000
ORDER BY broken_files DESC
LIMIT 10"

run 3 median-file-size.csv "SELECT
    quantileExact(0.50)(size)                               AS p50_bytes,
    formatReadableSize(quantileExact(0.50)(size))           AS p50_human,
    quantileExact(0.75)(size)                               AS p75_bytes,
    formatReadableSize(quantileExact(0.75)(size))           AS p75_human,
    quantileExact(0.90)(size)                               AS p90_bytes,
    formatReadableSize(quantileExact(0.90)(size))           AS p90_human,
    quantileExact(0.95)(size)                               AS p95_bytes,
    formatReadableSize(quantileExact(0.95)(size))           AS p95_human,
    avg(size)                                               AS avg_bytes,
    formatReadableSize(toUInt64(avg(size)))                 AS avg_human
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'"

run 4 tree-depth.csv "SELECT
    max(length(splitByChar('/', file_path)))                 AS max_depth,
    quantileExact(0.95)(length(splitByChar('/', file_path))) AS p95_depth,
    quantileExact(0.50)(length(splitByChar('/', file_path))) AS p50_depth
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'
  AND file_path != ''"

run 5 duplicate-floor.csv "WITH duplicate_clusters AS (
    SELECT
        filename,
        size,
        count()              AS copies,
        (count() - 1) * size AS wasted_bytes
    FROM symphony.scan_results
    WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233' AND size > 1048576
    GROUP BY filename, size
    HAVING copies > 1
)
SELECT
    count()                                 AS dup_clusters,
    sum(copies)                             AS total_duplicate_files,
    sum(wasted_bytes)                       AS total_wasted_bytes,
    formatReadableSize(sum(wasted_bytes))   AS total_wasted_human,
    sum(copies - 1)                         AS reclaimable_file_count
FROM duplicate_clusters"

run 6 size-distribution-6band.csv "SELECT
    multiIf(
        size < 102400,                              '1_<100K',
        size < 1048576,                             '2_100K-1M',
        size < 10485760,                            '3_1M-10M',
        size < 104857600,                           '4_10M-100M',
        size < 1073741824,                          '5_100M-1G',
        size < 10737418240,                         '6_1G-10G',
                                                    '7_>10G'
    )                                               AS size_band,
    count()                                         AS files,
    sum(size)                                       AS bytes,
    formatReadableSize(sum(size))                   AS bytes_human
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'
GROUP BY size_band
ORDER BY size_band"

run 7 protected-dacl.csv "SELECT
    countIf(positionCaseInsensitive(acl_analysis, 'P') > 0)                             AS protected_dacl_files,
    round(100.0 * countIf(positionCaseInsensitive(acl_analysis, 'P') > 0) / count(), 2) AS pct_protected_dacl,
    countIf(positionCaseInsensitive(acl_analysis, 'N') > 0)                             AS may_narrow_files,
    round(100.0 * countIf(positionCaseInsensitive(acl_analysis, 'N') > 0) / count(), 2) AS pct_may_narrow
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'"

run 8 year-2019-bulge.csv "SELECT
    splitByChar('/', file_path)[4]  AS dept,
    count()                         AS files_2019,
    sum(size)                       AS bytes_2019,
    formatReadableSize(sum(size))   AS bytes_human
FROM symphony.scan_results
WHERE run_id = 'c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233'
  AND toYear(created) = 2019
  AND splitByChar('/', file_path)[4] != ''
GROUP BY dept
ORDER BY files_2019 DESC
LIMIT 10"

if [ -n "$ERRORS" ]; then
    printf 'Failures:\n\n%b' "$ERRORS" > "$OUT/ERRORS.md"
    echo "ERRORS.md written"
fi
