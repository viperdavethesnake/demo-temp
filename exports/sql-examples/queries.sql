-- Working queries used across the four dashboards against `symphony.scan_results`.
-- ClickHouse dialect. All queries are parameterized on $run_id (the dashboard variable).
-- Run examples (no variable substitution) against ClickHouse HTTP:
--   curl -s "http://localhost:8123/?user=symphony&password=symphony" --data "<query>"

-- ---------------------------------------------------------------
-- Overview KPIs (sym-exec headline row)
-- ---------------------------------------------------------------
SELECT
    count()                                                                        AS total_files,
    sum(size)                                                                      AS total_bytes,
    formatReadableSize(sum(size))                                                  AS total_human,
    uniqExact(owner_sid)                                                           AS unique_owners,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 3 YEAR) / count(), 2)   AS pct_dormant_3y_access,
    round(100.0 * countIf(owner_name LIKE 'S-1-%' OR owner_name = '') / count(), 2) AS pct_orphan_sid,
    round(100.0 * countIf(positionCaseInsensitive(acl_analysis,'W') > 0) / count(), 2) AS pct_widens_access,
    round(100.0 * countIf(positionCaseInsensitive(acl_analysis,'B') > 0) / count(), 2) AS pct_broken_inherit
FROM symphony.scan_results
WHERE run_id = '$run_id';

-- ---------------------------------------------------------------
-- Department breakdown (sym-arch, sym-exec, sym-cfo)
-- Path shape: /S/Shared/<Dept>/...  (Symphony normalizes to forward slashes)
-- ---------------------------------------------------------------
SELECT
    splitByChar('/', file_path)[4]  AS dept,
    count()                         AS files,
    sum(size)                       AS bytes,
    formatReadableSize(sum(size))   AS bytes_human
FROM symphony.scan_results
WHERE run_id = '$run_id' AND dept != ''
GROUP BY dept
ORDER BY bytes DESC;

-- ---------------------------------------------------------------
-- Creation-year histogram (shows the 2019 Deadbeat bulge)
-- ---------------------------------------------------------------
SELECT
    toYear(created) AS year,
    count()         AS files,
    sum(size)       AS bytes
FROM symphony.scan_results
WHERE run_id = '$run_id' AND year BETWEEN 2015 AND 2027
GROUP BY year ORDER BY year;

-- ---------------------------------------------------------------
-- Chargeback (matches Symphony's native Chargeback Report, p.7)
-- UNATTRIBUTABLE = anything not owned by a DEMO\GG_* group:
--   orphan SIDs, BUILTIN\Administrators, DEMO\svc_*, direct users.
-- ---------------------------------------------------------------
SELECT
    multiIf(owner_name LIKE 'DEMO\\GG_%', owner_name, 'UNATTRIBUTABLE') AS chargeback_group,
    count()                                                            AS files,
    sum(size)                                                          AS bytes,
    formatReadableSize(sum(size))                                      AS bytes_human
FROM symphony.scan_results
WHERE run_id = '$run_id'
GROUP BY chargeback_group
ORDER BY bytes DESC;

-- ---------------------------------------------------------------
-- Ownership categories (matches generator's `b` bucket field)
-- ---------------------------------------------------------------
SELECT
    multiIf(
        owner_name LIKE 'S-1-%' OR owner_name = '',   'OrphanSid',
        owner_name LIKE 'DEMO\\svc_%',                'ServiceAccount',
        owner_name = 'BUILTIN\\Administrators',       'BuiltinAdmin',
        owner_name LIKE 'DEMO\\GG_%',                 'DeptGroup',
                                                      'User'
    ) AS bucket,
    count() AS files,
    sum(size) AS bytes
FROM symphony.scan_results
WHERE run_id = '$run_id'
GROUP BY bucket
ORDER BY files DESC;

-- ---------------------------------------------------------------
-- Dormancy by dept — the 70% "hasn't been touched" story, sliced by folder
-- ---------------------------------------------------------------
SELECT
    splitByChar('/', file_path)[4] AS dept,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 1 YEAR) / count(), 1) AS pct_aging_1y,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 3 YEAR) / count(), 1) AS pct_dormant_3y,
    round(100.0 * countIf(last_accessed < now() - INTERVAL 5 YEAR) / count(), 1) AS pct_ancient_5y,
    count() AS files
FROM symphony.scan_results
WHERE run_id = '$run_id' AND dept != ''
GROUP BY dept
HAVING files > 1000
ORDER BY files DESC;

-- ---------------------------------------------------------------
-- ACL hygiene via `acl_analysis` flag string (Symphony pre-computed)
--   W = may widen access     B = broken DACL inheritance
--   N = may narrow           P = protected DACL (inheritance disabled)
--   Z = NULL DACL (open to everyone)
-- ---------------------------------------------------------------
SELECT
    acl_analysis,
    count() AS files
FROM symphony.scan_results
WHERE run_id = '$run_id'
GROUP BY acl_analysis
ORDER BY files DESC
LIMIT 25;

-- ---------------------------------------------------------------
-- ACL-pattern classifier from the raw `acl` string
-- Useful for a sankey: where do ACEs come from?
-- ---------------------------------------------------------------
SELECT
    multiIf(
        positionCaseInsensitive(acl, 'DL_Share_')       > 0, 'ProperAGDLP',
        positionCaseInsensitive(acl, 'DEMO\\GG_')       > 0, 'LazyGG (direct global group on ACL)',
        positionCaseInsensitive(acl, 'Everyone')        > 0, 'Everyone',
        positionCaseInsensitive(acl, 'DENY')            > 0, 'Deny',
        positionCaseInsensitive(acl, 'S-1-5-21')        > 0, 'OrphanSid-ACE',
        'Other'
    ) AS pattern,
    count() AS files,
    sum(size) AS bytes
FROM symphony.scan_results
WHERE run_id = '$run_id'
GROUP BY pattern
ORDER BY files DESC;

-- ---------------------------------------------------------------
-- Top orphan SIDs (ex-employee file footprint)
-- ---------------------------------------------------------------
SELECT
    owner_sid,
    any(owner_name) AS sample_name,
    count()         AS files,
    sum(size)       AS bytes,
    min(modified)   AS oldest_touch,
    max(modified)   AS newest_touch
FROM symphony.scan_results
WHERE run_id = '$run_id' AND (owner_name LIKE 'S-1-%' OR owner_name = '')
GROUP BY owner_sid
ORDER BY files DESC
LIMIT 25;

-- ---------------------------------------------------------------
-- Service-account footprint (DEMO\svc_*)
-- ---------------------------------------------------------------
SELECT
    owner_name,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human
FROM symphony.scan_results
WHERE run_id = '$run_id' AND owner_name LIKE 'DEMO\\svc_%'
GROUP BY owner_name
ORDER BY files DESC;

-- ---------------------------------------------------------------
-- Top extensions by bytes (the .PDF / .BAK / .LOG story)
-- ---------------------------------------------------------------
SELECT
    extension,
    count() AS files,
    sum(size) AS bytes,
    formatReadableSize(sum(size)) AS bytes_human
FROM symphony.scan_results
WHERE run_id = '$run_id'
GROUP BY extension
ORDER BY bytes DESC
LIMIT 15;

-- ---------------------------------------------------------------
-- File size buckets (log-scale distribution)
-- ---------------------------------------------------------------
SELECT
    multiIf(size<1024, '<1K',
            size<1048576, '1K-1M',
            size<1073741824, '1M-1G',
            size<1099511627776, '1G-1T',
            '>1T') AS bucket,
    count() AS files,
    sum(size) AS bytes
FROM symphony.scan_results
WHERE run_id = '$run_id'
GROUP BY bucket
ORDER BY min(size);

-- ---------------------------------------------------------------
-- Duplicate candidates (naive filename+size — noisy; use hash when enabled)
-- ---------------------------------------------------------------
SELECT
    filename,
    size,
    count()                 AS copies,
    (count() - 1) * size    AS wasted_bytes
FROM symphony.scan_results
WHERE run_id = '$run_id' AND size > 1048576
GROUP BY filename, size
HAVING copies > 1
ORDER BY wasted_bytes DESC
LIMIT 50;
