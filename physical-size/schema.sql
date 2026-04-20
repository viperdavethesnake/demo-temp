-- symphony.file_physical
-- Sibling to symphony.scan_results, holds per-file NTFS-allocation bytes.
-- Owned by this project (not by Symphony AdminCenter's exporter).
--
-- Design rationale: see DESIGN.md §3.1 and CLICKHOUSE.md §2.

CREATE TABLE IF NOT EXISTS symphony.file_physical (
    run_id     String,
    file_uri   String,
    allocated  UInt64,
    probed_at  DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(probed_at)
PARTITION BY run_id
ORDER BY (run_id, file_uri);
