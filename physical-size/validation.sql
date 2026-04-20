-- Validation and progress queries for symphony.file_physical.
-- See CLICKHOUSE.md §7 for rationale. Substitute $run_id before running.

-- ----------------------------------------------------------------------------
-- Progress (tail this while the walker runs)
-- Done-check: probed = 9,962,001
-- ----------------------------------------------------------------------------
SELECT count() AS probed,
       min(probed_at) AS started,
       max(probed_at) AS latest
FROM symphony.file_physical
WHERE run_id = '$run_id';


-- ----------------------------------------------------------------------------
-- Coverage: expected vs probed. Shortfall = files the walker couldn't reach.
-- ----------------------------------------------------------------------------
SELECT
  (SELECT count() FROM symphony.scan_results   WHERE run_id='$run_id' AND filename != '') AS expected,
  (SELECT uniqExact(file_uri) FROM symphony.file_physical WHERE run_id='$run_id')         AS probed,
  expected - probed AS missing;


-- ----------------------------------------------------------------------------
-- Identify missing files (set-difference against scan_results)
-- ----------------------------------------------------------------------------
SELECT file_uri
FROM symphony.scan_results
WHERE run_id = '$run_id'
  AND filename != ''
  AND file_uri NOT IN (
    SELECT file_uri FROM symphony.file_physical WHERE run_id = '$run_id'
  )
LIMIT 100;


-- ----------------------------------------------------------------------------
-- Physical total — should land near the generator's ~1.2 TB
-- ----------------------------------------------------------------------------
SELECT formatReadableSize(sum(allocated)) AS physical_total
FROM symphony.file_physical
WHERE run_id = '$run_id';


-- ----------------------------------------------------------------------------
-- Logical vs physical ratio
-- ----------------------------------------------------------------------------
SELECT
  formatReadableSize((SELECT sum(size)      FROM symphony.scan_results  WHERE run_id='$run_id' AND filename!='')) AS logical,
  formatReadableSize((SELECT sum(allocated) FROM symphony.file_physical WHERE run_id='$run_id'))                  AS physical,
  round(
    (SELECT sum(allocated) FROM symphony.file_physical WHERE run_id='$run_id')
    / (SELECT sum(size)    FROM symphony.scan_results  WHERE run_id='$run_id' AND filename!=''),
    4
  ) AS physical_over_logical;


-- ----------------------------------------------------------------------------
-- Distribution of physical size (how many files at each allocation step)
-- ----------------------------------------------------------------------------
SELECT
  formatReadableSize(allocated) AS bucket,
  count() AS files,
  formatReadableSize(sum(allocated)) AS bytes
FROM symphony.file_physical
WHERE run_id = '$run_id'
GROUP BY allocated
ORDER BY allocated;


-- ----------------------------------------------------------------------------
-- Logical-vs-physical tile pair for sym-exec
-- ----------------------------------------------------------------------------
SELECT
  formatReadableSize(sum(sr.size))     AS logical_capacity,
  formatReadableSize(sum(fp.allocated)) AS on_disk_capacity
FROM symphony.scan_results sr
LEFT ANY JOIN (
  SELECT run_id, file_uri, argMax(allocated, probed_at) AS allocated
  FROM symphony.file_physical
  WHERE run_id = '$run_id'
  GROUP BY run_id, file_uri
) fp
  ON fp.run_id = sr.run_id AND fp.file_uri = sr.file_uri
WHERE sr.run_id = '$run_id' AND sr.filename != '';
