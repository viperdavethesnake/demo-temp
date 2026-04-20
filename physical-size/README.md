# physical-size

Second-pass walk that captures **NTFS on-disk allocation** per file and lands it in `symphony.file_physical` — a sibling table to Symphony's `symphony.scan_results`. Purpose: give dashboards a physical-capacity number to set next to Symphony's logical `size`, so the demo can tell the tiering story ("85.6 TB logical on 1.2 TB primary").

---

## Status

**Live as of 2026-04-20.** Full walk complete, data validated.

| Item | Value |
|---|---|
| run_id | `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233` |
| Rows in `file_physical` | **9,962,001** (exact match to `scan_results` WHERE `filename != ''`) |
| Coverage gap | **0** missing, 0 errors |
| Walk duration | 678.5 s (~11.3 min) at 14,683 rows/s |
| Table size on disk | 90.47 MiB compressed (1.56 GiB uncompressed) |

### The headline numbers

| | |
|---|---|
| Logical total (Symphony's `size`) | 77.87 TiB |
| Physical total (our `allocated`) | **1.13 TiB** |
| Ratio | 0.0145 (1.45 %) |
| Files allocated exactly 128 KiB | 9,015,627 (90.5 %) |
| Files allocated < 128 KiB | 946,374 (real content smaller than one NTFS cluster-group) |

Validates against the generator's declared ~1.2 TB physical footprint.

---

## What's next

1. **Dashboard wiring — primary task.** Add the Logical / On-Disk tile pair to `sym-exec` (or add a `$size_metric` variable that toggles per-panel). The query pattern is in `validation.sql`:

   ```sql
   SELECT
     formatReadableSize(sum(sr.size))      AS logical_capacity,
     formatReadableSize(sum(fp.allocated)) AS on_disk_capacity
   FROM symphony.scan_results sr
   LEFT ANY JOIN (
     SELECT run_id, file_uri, argMax(allocated, probed_at) AS allocated
     FROM symphony.file_physical
     WHERE run_id = '$run_id'
     GROUP BY run_id, file_uri
   ) fp ON fp.run_id = sr.run_id AND fp.file_uri = sr.file_uri
   WHERE sr.run_id = '$run_id' AND sr.filename != '';
   ```

   Runs in ~14 s over 9.96 M rows — fine for stat tiles that load once per view. If snappier interactivity is needed, **split into two independent `sum()` queries** (one per tile) and they return sub-second; or escalate to the dictionary pattern in `CLICKHOUSE.md` §5.2 (~1.5 GB server RAM, sub-second).

2. **(Optional) Decide which existing panels get a `$size_metric` toggle** vs stay logical-only. Small change; only worth doing on panels where physical vs logical tells a different story (capacity-oriented tiles, storage savings, etc.).

3. **(Deferred) Tiered-customer scan.** Once we get a real tenant with `storage_class` / `storage_state` populated, revisit — on such a scan, the interesting metric shifts from "sparse vs allocated" to "on-primary vs stubbed."

---

## File map

| File | Purpose |
|---|---|
| `README.md` | **← you are here** — status, next steps, operations |
| `DESIGN.md` | Original proposal; architectural rationale for option C, why a sibling table not a scan_results column, walker spec, out-of-scope boundaries |
| `CLICKHOUSE.md` | Integration mechanics: schema choices (ReplacingMergeTree + PARTITION BY run_id), load pipeline, LEFT JOIN vs dictionary tradeoff, validation queries, confirmed-facts table |
| `NOTES.md` | **Append-only run log.** Bring-up gotchas (string-format operator inside method parens, explicit INSERT column list, `Console.In.EndOfStream` hang), smoke results, full-walk results |
| `schema.sql` | `CREATE TABLE symphony.file_physical` |
| `validation.sql` | Progress, coverage, ratio, distribution, and the sym-exec tile-pair query |
| `probe-physical-size.ps1` | PowerShell 7 walker (stdin TSV → batched HTTP POST into ClickHouse) |
| `load-physical-size.sh` | Driver that pre-flights, runs the walker, reports validation |

Not committed (gitignored): `walker-errors.log`, `failed-batches/`.

---

## Operations

### Re-walk the same run_id

```bash
cd physical-size
./load-physical-size.sh   # defaults to the current run_id
```

`ReplacingMergeTree(probed_at)` + `PARTITION BY run_id` means the new rows replace the old on background merge. Reads remain correct throughout (the tile query uses `argMax(allocated, probed_at)`).

### Walk a different run_id

```bash
./load-physical-size.sh <new-run-id>
```

### Wipe a run's physical data

```sql
ALTER TABLE symphony.file_physical DROP PARTITION '<run-id>';
```

### Apply the schema on a fresh server

```bash
curl -u symphony:symphony http://localhost:8123/ --data-binary @physical-size/schema.sql
```

### Spot-check

```bash
curl -s -u symphony:symphony "http://localhost:8123/" \
  --data-binary "SELECT count(), formatReadableSize(sum(allocated))
                 FROM symphony.file_physical
                 WHERE run_id = 'c915d505-...'"
# -> 9962001   1.13 TiB
```

---

## Prerequisites for any re-run

1. **WSL must be Running** (keepalive process alive — see `../RESUME.md` and the `project_symphony_clickhouse` memory). A cold WSL VM stalls ClickHouse reads mid-walk.
2. **`S:\Shared` must be mounted** — the walker resolves Symphony URIs to `S:\` paths.
3. **PowerShell 7** on PATH (`pwsh`).
4. **ClickHouse reachable** at `http://localhost:8123` with `symphony:symphony` credentials.

`load-physical-size.sh` checks all of these before starting and fails with a clear message if any are missing.

---

## Why there's no "rows with status=ERROR"

The schema deliberately omits a status column — rows only exist for successful probes, and missing files are identified by set-difference against `scan_results` at validation time. On this run the set-difference is empty (0 missing). On a future run with real errors, the query to find them is in `validation.sql`:

```sql
SELECT file_uri
FROM symphony.scan_results
WHERE run_id = '$run_id' AND filename != ''
  AND file_uri NOT IN (
    SELECT file_uri FROM symphony.file_physical WHERE run_id = '$run_id'
  ) LIMIT 100;
```

---

## Out of scope for this folder

- Dashboard panel *layout* changes (year histogram, dept treemap, dormancy heatmap) — those are `docs/backlog.md` items 0b / 0c / 0d, owned by the dashboard work.
- `migrated` / `storage_class` / `storage_state` tiles — deferred until a real tiered-customer scan.
