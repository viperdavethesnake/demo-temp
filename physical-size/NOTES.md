# Walker run log

Append-only. Record each full or partial walk: `run_id`, start/end, elapsed, rows inserted, errors, surprises.

---

## 2026-04-20 — 20-file spot-check (pre-walker)

- Purpose: validate `GetCompressedFileSizeW` path end-to-end before writing the walker.
- Script: `tmp/physical-size-probe.ps1` (throwaway).
- Sample: 20 files, stratified across size buckets (1 KB → 1.4 GB).
- Result: 20/20 succeeded, zero errors. Every sparse file allocated exactly 131,072 B (128 KB = 32 × 4 KB clusters); files ≤ 10 KB stored 1:1.
- Extrapolation: 9.96 M × ~128 KB ≈ 1.28 TB, consistent with the generator's stated ~1.2 TB physical footprint.

---

## 2026-04-20 — Walker smoke tests

Two issues found and fixed during bring-up:

1. **String-format bug in buffer.Add.** `"{0}`t{1}`t{2}" -f $a, $b, $c` inside a `.Add(...)` call parses as three method args because commas inside method parens are arg separators, not `-f` list separators. Wrap the format expression in parens: `.Add(("..." -f $a, $b, $c))`.
2. **INSERT missing column list.** Table has four columns; walker sends three (probed_at has DEFAULT now()). ClickHouse rejects with "expected '\t' before '\n'" until the URL is changed to `INSERT INTO symphony.file_physical (run_id, file_uri, allocated) FORMAT TabSeparated`.
3. **`[Console]::In.EndOfStream` hung** after the last batch on redirected stdin. Replaced with `ReadLine()` + null check.

Throughput: 10K files in 2.1s = **~4,800 rows/s steady state** (first batch warm-up ~2,500/s). Projected full walk: ~35 min single-threaded. Parallelism not pursued — complexity not worth the ~5-10 min saving.

Physical sum per 10K files: 1.16 GiB → extrapolated 1.16 TB for full dataset. Matches the ~1.2 TB target.
