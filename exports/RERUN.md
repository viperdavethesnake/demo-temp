# Rerun plan — regenerate S:\Shared, compare against current baseline

**Status (paused 2026-04-20):** shutting down to grow the data disk. Resume from step 1 below.

## Why

The v0.2 report had invented paths and some dataset artifacts (e.g. age-band distribution, 2019 bulge shape) that looked thin. Goal is to regenerate the synthetic content at `S:\Shared` and see if the resulting scan produces more plausible numbers across the 8 gap-fill queries. Current dataset stays the gold baseline until the new one is proven better.

## Baseline (frozen)

- **Commit:** `4cc11b8c6ce75db1a3f0296d0e752df5854d7ec9` on `main`
- **run_id:** `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233`
- **CSVs:** `exports/source-data/v0.3-gap-fills/` (8 files, all queries succeeded)
- **Query runner:** `exports/sql-examples/run-v0.3-gap-fills.sh`
- **Row count:** 9,964,693 files · 77.87 TiB logical

Do not wipe ClickHouse. The baseline `run_id` must remain queryable in `symphony.scan_results` for side-by-side comparison.

## Before regenerating — decisions still open

1. **Is `build-10M.ps1` deterministic?** If it uses `Get-Random` without a fixed seed, we cannot reproduce a specific new dataset later. If reproducibility matters for the next report revision, seed it and commit the seed. Check before regenerating.
2. **What does "looks better" mean?** Pick 3–4 concrete criteria before regenerating so we evaluate against a target, not vibes. Candidates:
   - Top-10 broken-inheritance directories are believable paths (not artifacts of the generator)
   - Age-band distribution is not dominated by one band
   - 2019 bulge shows up concentrated in 2–3 departments, not smeared
   - Median/p95 file sizes are in realistic ranges for the department mix

## Cycle (when resuming)

1. Grow data disk, boot back up.
2. (Optional but recommended) Seed `build-10M.ps1` before running; record the seed.
3. Wipe `S:\Shared` content, run the generator to repopulate.
4. Run Symphony scan using the same policy/selections as the baseline scan.
5. Confirm new `run_id` appears in `symphony.scan_results` — do **not** drop the table. Note the new UUID.
6. Copy `exports/sql-examples/run-v0.3-gap-fills.sh` → `run-v0.3-gap-fills-run2.sh` (or parameterize via a shared var), substitute the new run_id, and output to `exports/source-data/v0.3-gap-fills-run2/`.
7. Diff the two CSV sets. If the new run wins across the criteria above, it becomes the new baseline (update `HANDOFF.md` and the v0.3 report sources). If not, keep the baseline and iterate the generator.

## Parameterization TODO (after a successful second run)

The run_id is currently hardcoded in 8 places in `run-v0.3-gap-fills.sh`. When we commit to a second run, pull it out to a single shell variable (or env var) so future reruns become a one-line edit. Same for dashboards if they embed run_id in panel queries — worth a grep pass before the next cycle.
