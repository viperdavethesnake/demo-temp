-- ClickHouse DDL for sym02's symphony.scan_results — live export.
-- Source: SHOW CREATE TABLE symphony.scan_results on the sym02 ClickHouse, 2026-04-20.
-- This is the sym02 source of truth. All SQL for sym02 dashboards targets this column list.
--
-- Notes for dashboard work:
--   * `migrated Bool` — % stubbed to archive tier. Backlog item #2.
--   * `acl_analysis String` — Symphony's pre-computed flag string
--     (B = broken DACL inheritance, W = may widen access, Z = NULL DACL, etc.).
--     Use this instead of substring/regex on `acl` / `parent_acl`.
--   * `storage_class`, `storage_state` — tiered-storage location. Backlog item #3.
--   * `last_accessed` — use alongside or in place of `modified` for true cold set. Backlog item #4.
--   * `ingest_created`, `ingest_modified` — Symphony scan-time timestamps, distinct
--     from filesystem created/modified. Not referenced by any current panel; candidate
--     for a future scan-coverage / partial-scan-detection panel.
--
-- Engine note:
--   Table is `ENGINE = MergeTree ORDER BY file_uri` with no PARTITION BY.
--   $run_id filters in Grafana don't hit the primary index and will full-scan a
--   single run_id lookup. Fine at ~7M rows; monitor at full-scan scale. Not in
--   scope for this dashboard-fix session — flag to DDL owner if perf becomes an issue.

CREATE TABLE symphony.scan_results
(
    `run_id` String,
    `run_start_time` String,
    `file_uri` String,
    `file_path` String,
    `filename` String,
    `extension` String,
    `size` UInt64,
    `migrated` Bool,
    `owner_name` String,
    `owner_sid` String,
    `acl` String,
    `acl_analysis` String,
    `parent_acl` String,
    `win_ads_names` String,
    `created` DateTime64(3),
    `modified` DateTime64(3),
    `last_accessed` DateTime64(3),
    `ingest_created` DateTime64(3),
    `ingest_modified` DateTime64(3),
    `storage_class` String,
    `storage_state` String,
    `version_id` String
)
ENGINE = MergeTree
ORDER BY file_uri
SETTINGS index_granularity = 8192;
