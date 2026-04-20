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
    probed_at  DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(probed_at)
PARTITION BY run_id
ORDER BY (run_id, file_uri);
```

- Same `ORDER BY` as `scan_results` so joins are efficient.
- `ReplacingMergeTree(probed_at)` + `PARTITION BY run_id` — safe re-probe (latest `probed_at` wins per key) and clean drop-old-run via `ALTER TABLE DROP PARTITION`.
- **No status column.** Rows exist only for successful probes. Files the walker couldn't reach (deleted, permission error, Win32 failure) are found via set-difference against `scan_results` at validation time — simpler schema, same information. See `CLICKHOUSE.md` §2 for the full rationale.

### 3.2 Walker (`probe-physical-size.ps1`)

PowerShell 7 script at `physical-size/probe-physical-size.ps1`.

- **Input:** reads `(run_id, file_uri)` as TSV on stdin (streamed from ClickHouse). Caller filters `WHERE filename != ''` to exclude the 2,692 directory rows.
- **Output:** inserts directly into ClickHouse via batched HTTP POSTs — the walker owns writes, nothing comes back on stdout.
- **Path conversion:** `win://<host>/<drive>/<rest>` → `<drive>:\<rest-with-\-and-URL-decoded>`. Max URI length in the dataset is 144 chars — `\\?\` prefix not required here, but the walker should still emit it for paths > 248 chars so the same code survives a future customer scan.
- **API:** P/Invoke `GetCompressedFileSizeW`. Already validated in `tmp/physical-size-probe.ps1`.
- **Parallelism:** `ForEach-Object -Parallel -ThrottleLimit 8`. Disk is NVMe; Win32 metadata calls are cheap but the file set is 10 M, so parallelism matters.
- **Batched inserts:** buffer successful probes in memory, flush every **10,000–50,000 rows** (target 25,000) via HTTP POST to `http://localhost:8123/?query=INSERT+INTO+symphony.file_physical+FORMAT+TabSeparated` with Basic auth `symphony:symphony`. Retry with exponential backoff (3 attempts: 1 s / 4 s / 16 s); on final failure, dump the batch to `physical_sizes.failed-<ts>.tsv` and continue. See `CLICKHOUSE.md` §3.2.
- **Error handling:** file-not-found and Win32 errors are logged to a sidecar log file and the row is skipped — no "error" row is written. Missing files are reconstructed at validation time via set-diff against `scan_results`.
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

Queries live in `CLICKHOUSE.md` §7; acceptance bar:

1. **Done-check:** `count() FROM symphony.file_physical WHERE run_id='$run_id'` = **9,962,001**.
2. `sum(allocated)` lands within ~5 % of 1.2 TB (the generator's stated physical total).
3. Spot-check: re-run the 20-file probe on the same URIs and confirm `allocated` matches what's in the table.
4. Set-diff (expected vs probed) yields fewer than ~10,000 missing files (< 0.1 %). Anything higher implies a walker bug, not data rot.

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

Steps 1–5 complete as of 2026-04-20. See `NOTES.md` for the run log and `README.md` for the headline numbers.

1. ~~5-min Scan Policy wizard check.~~ **Done** — Symphony's Scan Policy has no native allocated/physical-size field. Evidence: `scan_results` schema has one `size UInt64` (no `allocated`/`physical`/`on_disk` column); admin guide §G.3.2–§G.3.3 describe "file metadata export to database" with zero mention of physical/allocated/compressed size. Walker is required.
2. ~~Create `symphony.file_physical` table.~~ **Done** — DDL in `schema.sql`, applied to `localhost:8123`.
3. ~~Write `probe-physical-size.ps1`; smoke-test.~~ **Done** — 1K-file and 10K-file smokes passed, three bring-up fixes captured in `NOTES.md` (format-operator precedence inside `.Add()`, explicit INSERT column list for DEFAULT'd `probed_at`, `Console.In.EndOfStream` replaced with `ReadLine() != $null`).
4. ~~Full walk.~~ **Done** — 9,962,001 files probed in 678.5 s at 14,683 rows/s, zero errors, zero missing.
5. ~~Validation.~~ **Done** — physical total 1.13 TiB against ~1.2 TB target; coverage 100 %; distribution matches expectation (90.5 % of files at the 128 KiB sparse floor).
6. **Next:** prototype the side-by-side Logical / On-Disk tiles on `sym-exec` (query pattern in `validation.sql`).
7. **Next:** decide which other panels get `$size_metric` vs stay logical-only.

## 8. Files this folder will hold

- `DESIGN.md` — this document (goals, method, validation, out-of-scope).
- `CLICKHOUSE.md` — schema, load pipeline, join vs dictionary tradeoff, validation queries, confirmed facts table.
- `schema.sql` — `CREATE TABLE symphony.file_physical`.
- `probe-physical-size.ps1` — the walker.
- `load-physical-size.sh` — driver that streams from ClickHouse through the walker back into ClickHouse.
- `validation.sql` — the queries behind §4 / `CLICKHOUSE.md` §7.
- `NOTES.md` — append-only log of what happened on each walk (run_id, duration, error rate, surprises).
