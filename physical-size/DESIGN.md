# Physical (on-disk) Size — Design Plan

**Status:** proposed, pre-implementation
**Author:** new-chat pickup of `docs/prompts/real-size.md`
**Date:** 2026-04-20
**Scope:** add a second, allocation-aware size column alongside Symphony's logical `size` so dashboards can tell the "85.6 TB logical on 1.2 TB primary" story.

---

## 1. Decision

- **Interpretation:** (C) both — keep Symphony's logical `size` untouched, add a sibling column for on-disk allocation, let dashboards choose.
- **Method:** second-pass walk of `S:\Shared`, one Win32 call per file, results loaded into a new ClickHouse table. **No changes to `symphony.scan_results`.**
- **Rationale:** this is a method we would show a customer, so the lab needs to exercise a real per-file probe — not a synthetic multiplier — even though on *this* sparse dataset a computed column would give the same aggregate answer.

## 2. What the 20-file probe told us

From `tmp/physical-size-probe.ps1` on 20 stratified samples (2026-04-20):

| Logical size bucket | Files | Physical | Ratio |
|---|---|---|---|
| 1 KB – 10 KB | 5 | == logical | 1.00 |
| 323 KB – 1.4 GB | 15 | flat **131,072 B** | 0.40 → 0.0001 |

- Every sparse file allocates exactly one NTFS cluster (128 KB) on this volume.
- Files already smaller than a cluster are stored 1:1.
- Extrapolated total: 9,962,001 × ~128 KB ≈ **1.28 TB**, matching the generator's declared ~1.2 TB physical footprint.
- URI → Windows path conversion (incl. `%20` unescaping) works.
- `GetCompressedFileSizeW` via P/Invoke works, no errors on the sample.

Implications for the walker:
- Every file gets probed — no value in heuristics once we're walking anyway.
- Output is bounded: allocation will never exceed `size` + a cluster, so `UInt64` is plenty.
- Errors will be rare; we still capture a `status` column so gaps don't silently bias totals.

## 3. Target architecture

```
symphony.scan_results  ──(run_id, file_uri)──>  symphony.file_physical
        (logical)                                    (physical)
              \                                       /
               \─────────── JOIN in panel queries ───/
                               │
                               ▼
                   $size_metric = Logical | Physical
                   (Grafana dashboard variable)
```

### 3.1 New ClickHouse table

```sql
CREATE TABLE symphony.file_physical (
    run_id     String,
    file_uri   String,
    allocated  UInt64,
    status     LowCardinality(String),  -- OK | MISSING | ERROR
    probed_at  DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree
ORDER BY (run_id, file_uri);
```

- Same `ORDER BY` as `scan_results` so joins are efficient.
- `status` lets dashboards decide whether to include partial runs; `ERROR` rows carry `allocated = 0`.
- One row per `scan_results` row per probe. Re-probing the same `run_id` inserts new rows; if we care about deduping, we add a follow-up `OPTIMIZE` or switch to `ReplacingMergeTree(probed_at)`. Decide after first run.

### 3.2 Walker (`probe-physical-size.ps1`)

PowerShell 7 script at `physical-size/probe-physical-size.ps1`.

- **Input:** reads `(run_id, file_uri)` as TSV on stdin (streamed from `clickhouse-client`). Caller filters `WHERE filename != ''` to exclude the 2,692 directory rows.
- **Output:** writes `(run_id, file_uri, allocated, status)` as TSV to stdout.
- **Path conversion:** `win://<host>/<drive>/<rest>` → `<drive>:\<rest-with-\-and-URL-decoded>`. Max URI length in the dataset is 144 chars — `\\?\` prefix not required here, but the walker should still emit it for paths > 248 chars so the same code survives a future customer scan.
- **API:** P/Invoke `GetCompressedFileSizeW`. Already validated in `tmp/physical-size-probe.ps1`.
- **Parallelism:** `ForEach-Object -Parallel -ThrottleLimit 8`. Disk is NVMe; Win32 metadata calls are cheap but the file set is 10 M, so parallelism matters.
- **Error handling:**
  - File not found → emit row with `status=MISSING`, `allocated=0`.
  - Win32 error → emit row with `status=ERROR`, `allocated=0`. Log the error code to a sidecar log file; do not let one bad path stop the run.
- **Checkpointing:** write output incrementally (flush every N rows). If the walker dies, next run can resume by joining against rows already in `file_physical` and probing only the missing `file_uri`s.
- **Throughput budget:** target < 30 min for 10 M files. If we overshoot, switch to a small .NET tool — same APIs, lower overhead per call.

### 3.3 Load script (`load-physical-size.sh`)

Bash pipeline:

```
clickhouse-client -q "SELECT run_id, file_uri FROM symphony.scan_results WHERE run_id='$RUN_ID' FORMAT TabSeparated" \
  | pwsh -File probe-physical-size.ps1 \
  | tee physical_sizes.tsv \
  | clickhouse-client -q "INSERT INTO symphony.file_physical (run_id, file_uri, allocated, status) FORMAT TabSeparated"
```

`tee` gives us a local artifact so we can re-load without re-walking if ClickHouse import fails.

### 3.4 Dashboard integration

- Add Grafana template variable `$size_metric` with two values: `Logical`, `Physical`.
- Panels that need the toggle pattern:
  ```sql
  SELECT sum(
    CASE WHEN '$size_metric' = 'Physical' THEN fp.allocated ELSE sr.size END
  ) AS bytes
  FROM symphony.scan_results sr
  LEFT JOIN symphony.file_physical fp
    ON fp.run_id = sr.run_id AND fp.file_uri = sr.file_uri
  WHERE sr.run_id = '$run_id'
  ```
  `LEFT JOIN` so we degrade gracefully if the physical walk hasn't run for this `run_id`.
- New tiles on `sym-exec`: **Logical Capacity** (85.6 TB) and **On-Disk Capacity** (1.2 TB) side by side. The delta is the tiering story.
- Which existing panels get the toggle vs stay logical-only is a call for later — defer until data lands.

## 4. Validation / acceptance

1. Row count in `file_physical` equals row count in `scan_results` for the same `run_id`, ± `MISSING`/`ERROR`.
2. `sum(allocated)` lands within 5 % of 1.2 TB (the generator's stated physical total).
3. Spot-check: re-run the 20-file probe on the same URIs and confirm `allocated` matches what's in the table.
4. Count of `status != 'OK'` rows is < 0.1 % of the total (lab disk is stable; anything higher implies a walker bug, not data rot).

## 5. Risks & open questions

- **Long paths.** Dataset max is 144 chars — not a risk here. Walker still emits the `\\?\` prefix above 248 chars so a real-customer rescan is safe.
- **File deleted between scan and probe.** Expected rare on this static lab; rows logged as `MISSING`. Larger concern on a real customer — document as a known caveat.
- **Re-probe semantics.** Solved by `ReplacingMergeTree(probed_at)` + `PARTITION BY run_id` (see `CLICKHOUSE.md` §2 and §6). Re-walking appends and background-merge dedupes; forced reset is `ALTER TABLE DROP PARTITION`.
- **Keepalive.** WSL must stay warm for ClickHouse reads/writes throughout the walk (see `RESUME.md` cold-start gotcha). Walker pings `http://localhost:8123/ping` before starting and aborts with a clear message if ClickHouse doesn't respond.
- **Symphony native support — resolved.** No native allocated-size field exists (see §7). Walker is the only path.

## 6. Out of scope

Carrying forward from `docs/prompts/real-size.md`:

- Dashboard layout additions (year histogram, dept treemap, dormancy heatmap) — those are `docs/backlog.md` items 0b/0c/0d, handled by the other chat.
- `migrated` / `storage_class` / `storage_state` tiles — deferred until a real tiered-customer scan.
- Per-dashboard Grafana JSON surgery for the `$size_metric` variable — defer until the table is populated.

## 7. Execution order

1. ~~5-min Scan Policy wizard check~~ — **done 2026-04-20**. Symphony's Scan Policy has no native allocated/physical-size field. Evidence: `scan_results` schema has one `size UInt64` (no `allocated`/`physical`/`on_disk` column); admin guide §G.3.2–§G.3.3 describe "file metadata export to database" with zero mention of physical/allocated/compressed size. Walker is required.
2. Create `symphony.file_physical` table (SQL file in this folder — schema in `CLICKHOUSE.md` §2).
3. Write `probe-physical-size.ps1`; smoke-test on the same 20 URIs as the 2026-04-20 probe.
4. Full walk of active `run_id` (`c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233`) — 9,962,001 files after excluding 2,692 directory rows. Capture wall-clock and error-row count.
5. Run validation checks (§4 here and `CLICKHOUSE.md` §7).
6. Prototype the side-by-side Logical/On-Disk tiles on `sym-exec`.
7. Decide which other panels get `$size_metric` vs stay logical-only.

## 8. Files this folder will hold

- `DESIGN.md` — this document (goals, method, validation, out-of-scope).
- `CLICKHOUSE.md` — schema, load pipeline, join vs dictionary tradeoff, validation queries, confirmed facts table.
- `schema.sql` — `CREATE TABLE symphony.file_physical`.
- `probe-physical-size.ps1` — the walker.
- `load-physical-size.sh` — driver that streams from ClickHouse through the walker back into ClickHouse.
- `validation.sql` — the queries behind §4 / `CLICKHOUSE.md` §7.
- `NOTES.md` — append-only log of what happened on each walk (run_id, duration, error rate, surprises).
