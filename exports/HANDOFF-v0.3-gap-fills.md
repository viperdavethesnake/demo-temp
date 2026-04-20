# v0.3 Gap-Fill Queries — Claude Code task brief

## What to do with it

Ask Claude Code in the VM to:

- Open `exports/sql-examples/v0.3-gap-fill-queries.sql`
- Run each of the 8 queries against ClickHouse, substituting `$run_id` with the literal UUID `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233`
- Save the results as CSVs in a new folder `exports/source-data/v0.3-gap-fills/` using the filenames called out in the comments:
  - `age-bands-last-accessed.csv`
  - `top-dirs-broken-inheritance.csv`
  - `median-file-size.csv`
  - `tree-depth.csv`
  - `duplicate-floor.csv`
  - `size-distribution-6band.csv`
  - `protected-dacl.csv`
  - `year-2019-bulge.csv`

The curl invocation is in the file header. Claude Code should recognize the pattern from the existing `export-source-data.sh` in that folder.

## What each query unblocks

| # | Query | Unblocks |
|---|-------|----------|
| 1 | Age bands by last_accessed | Aileron cover + Crestline cover hero chart, Exec p3 Fig 1, Architect p6 Fig 7 — 4 pages |
| 2 | Top-10 broken-inheritance directories | Aileron p5 Ops worklist table (currently has invented paths — replaces the single biggest fiction in v0.2) |
| 3 | Median file size (p50/p75/p90/p95 + avg) | Aileron p6 tile — plus richer distribution context if we want it |
| 4 | Tree depth max/p95/p50 | Aileron p6 tile |
| 5 | Duplicate floor summary | Aileron p6 tile + p7 recommendation card 04 |
| 6 | 6-band size distribution | Aileron p6 Fig 6 — matches v0.2 granularity, no chart redesign needed |
| 7 | Protected DACL count | Optional — only if we decide to keep that tile instead of swapping to Service Accounts |
| 8 | 2019 bulge by department | New Architect-page finding — sharpens "investigate origin" language per decision C |

## After Claude Code runs it

Ping me with either:

- "Done, results are in `exports/source-data/v0.3-gap-fills/`" — I'll read the CSVs and start editing HTML
- Or paste the 8 result sets directly into chat — I'll read from there
