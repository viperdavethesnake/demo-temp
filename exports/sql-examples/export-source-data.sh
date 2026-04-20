#!/bin/bash
# Regenerate source-data CSVs from current ClickHouse scan_results.
# Run inside WSL Ubuntu-24.04.

set -euo pipefail
CH='http://localhost:8123/?user=symphony&password=symphony'
OUT="/mnt/c/Users/Administrator/Documents/claude/symphony/exports/source-data"
mkdir -p "$OUT"

q() { curl -s "$CH" --data "$1"; }

# Headline overview
q "SELECT
    count() AS files,
    sum(size) AS logical_bytes,
    formatReadableSize(sum(size)) AS logical_human,
    uniqExact(owner_sid) AS unique_owners,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 3 YEAR) / count(), 2) AS pct_dormant_3y,
    round(100.0 * countIf(owner_name LIKE 'S-1-%' OR owner_name = '') / count(), 2) AS pct_orphan,
    round(100.0 * countIf(positionCaseInsensitive(acl_analysis,'W') > 0) / count(), 2) AS pct_widens_access,
    round(100.0 * countIf(positionCaseInsensitive(acl_analysis,'B') > 0) / count(), 2) AS pct_broken_inherit
FROM symphony.scan_results FORMAT CSVWithNames" > "$OUT/overview.csv"

# Dept breakdown (top-level folder under /S/Shared/)
q "SELECT
    splitByChar('/', file_path)[4] AS dept,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human,
    round(100.0 * sum(size) / (SELECT sum(size) FROM symphony.scan_results), 2) AS pct_bytes
FROM symphony.scan_results
GROUP BY dept HAVING dept != ''
ORDER BY bytes DESC FORMAT CSVWithNames" > "$OUT/dept-breakdown.csv"

# Creation-year histogram (2019 bulge visible)
q "SELECT
    toYear(created) AS year,
    count() AS files,
    sum(size) AS bytes,
    round(100.0 * count() / (SELECT count() FROM symphony.scan_results), 2) AS pct_files
FROM symphony.scan_results
WHERE year BETWEEN 2015 AND 2027
GROUP BY year ORDER BY year FORMAT CSVWithNames" > "$OUT/year-distribution.csv"

# ACL analysis flag distribution
q "SELECT
    acl_analysis,
    count() AS files,
    round(100.0 * count() / (SELECT count() FROM symphony.scan_results), 2) AS pct
FROM symphony.scan_results
GROUP BY acl_analysis
ORDER BY files DESC LIMIT 50 FORMAT CSVWithNames" > "$OUT/acl-analysis-flags.csv"

# Ownership categories
q "SELECT
    multiIf(
        owner_name LIKE 'S-1-%' OR owner_name = '', 'OrphanSid',
        owner_name LIKE 'DEMO\\\\svc_%', 'ServiceAccount',
        owner_name = 'BUILTIN\\\\Administrators', 'BuiltinAdmin',
        owner_name LIKE 'DEMO\\\\GG_%', 'DeptGroup',
        'User'
    ) AS bucket,
    count() AS files,
    sum(size) AS bytes,
    round(100.0 * count() / (SELECT count() FROM symphony.scan_results), 2) AS pct_files
FROM symphony.scan_results
GROUP BY bucket ORDER BY files DESC FORMAT CSVWithNames" > "$OUT/ownership.csv"

# Top extensions by bytes and by count
q "SELECT
    extension,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human
FROM symphony.scan_results
GROUP BY extension ORDER BY bytes DESC LIMIT 25 FORMAT CSVWithNames" > "$OUT/extensions-by-bytes.csv"

q "SELECT
    extension,
    count() AS files,
    sum(size) AS bytes
FROM symphony.scan_results
GROUP BY extension ORDER BY files DESC LIMIT 25 FORMAT CSVWithNames" > "$OUT/extensions-by-count.csv"

# File size buckets
q "SELECT
    multiIf(size<1024,'<1K', size<1048576,'1K-1M', size<1073741824,'1M-1G', size<1099511627776,'1G-1T','>1T') AS bucket,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human
FROM symphony.scan_results
GROUP BY bucket ORDER BY min(size) FORMAT CSVWithNames" > "$OUT/size-buckets.csv"

# Dormancy by dept (based on last_accessed)
q "SELECT
    splitByChar('/', file_path)[4] AS dept,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 1 YEAR) / count(), 1) AS pct_aging_1y,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 3 YEAR) / count(), 1) AS pct_dormant_3y,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 5 YEAR) / count(), 1) AS pct_ancient_5y,
    count() AS files
FROM symphony.scan_results
GROUP BY dept HAVING dept != '' AND files > 1000
ORDER BY files DESC FORMAT CSVWithNames" > "$OUT/dormancy-by-dept.csv"

# Top orphan SIDs (ex-employee files)
q "SELECT
    owner_sid,
    any(owner_name) AS sample_name,
    count() AS files,
    sum(size) AS bytes
FROM symphony.scan_results
WHERE owner_name LIKE 'S-1-%' OR owner_name = ''
GROUP BY owner_sid
ORDER BY files DESC LIMIT 25 FORMAT CSVWithNames" > "$OUT/top-orphan-sids.csv"

# Service-account footprint
q "SELECT
    owner_name,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human
FROM symphony.scan_results
WHERE owner_name LIKE 'DEMO\\\\svc_%'
GROUP BY owner_name ORDER BY files DESC FORMAT CSVWithNames" > "$OUT/service-accounts.csv"

# Chargeback-style allocation (matches Symphony's native Chargeback Report)
q "SELECT
    multiIf(
        owner_name LIKE 'DEMO\\\\GG_%', owner_name,
        'UNATTRIBUTABLE'
    ) AS chargeback_group,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human
FROM symphony.scan_results
GROUP BY chargeback_group ORDER BY bytes DESC FORMAT CSVWithNames" > "$OUT/chargeback.csv"

echo "Done. CSVs in: $OUT"
ls -la "$OUT"
