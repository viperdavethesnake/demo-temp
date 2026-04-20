# Source-data CSVs

One CSV per "shape of story" the dashboards tell. Generated against the full scan (9.96M rows / 77.87 TiB, run_id `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233`, scanned 2026-04-20).

Regenerate anytime by re-running the queries in `../sql-examples/queries.sql` against ClickHouse, or by running `../sql-examples/export-source-data.sh` inside WSL on the demo host.

## Files

| CSV | What it contains | Demo storyline |
|---|---|---|
| `overview.csv` | Headline KPIs: total files/bytes, dormancy %, orphan %, W/B flag % | All dashboards' top row |
| `dept-breakdown.csv` | Files + bytes per dept (top-level folder under `/S/Shared/`) | IT bloat (15.2 TiB / 19% of total) |
| `year-distribution.csv` | Files + bytes by `toYear(created)`, 2015-2027 | 2019 Deadbeat acquisition bulge |
| `ownership.csv` | Files bucketed into DeptGroup/User/OrphanSid/BuiltinAdmin/ServiceAccount | Matches generator spec exactly (55/25/10/5/5) |
| `chargeback.csv` | Bytes per GG_\* owner + UNATTRIBUTABLE bucket | Matches Symphony's native Chargeback Report (PDF page 7) |
| `acl-analysis-flags.csv` | Distinct `acl_analysis` flag strings with counts | ACL hygiene: 92.6% broken-inheritance, 3.8% widens access |
| `top-orphan-sids.csv` | Top 25 deleted-account SIDs by file count | Ghost owners story (40 ex-employees, 10% of files) |
| `service-accounts.csv` | Per-svc-account file footprint (DEMO\svc_\*) | Service account sprawl (5% of files, 10 accounts) |
| `extensions-by-bytes.csv` | Top extensions by bytes | .PDF / .BAK / .LOG dominate bytes despite small count |
| `extensions-by-count.csv` | Top extensions by file count | .PDF tops both counts; .BAK is big-per-file |
| `size-buckets.csv` | Log-scale size distribution | Most files in 1M–1G bucket |
| `dormancy-by-dept.csv` | % files cold (1y/3y/5y) per dept | The 70% dormancy story, sliced |

## Column naming conventions

- Byte columns: `bytes` = raw `UInt64` integer, `bytes_human` = `formatReadableSize(...)` pre-formatted ("14.81 TiB")
- Percentages: stored as float `0.0–100.0`, not a fraction
- `files` is always an integer row count; `size` is the logical file size (sparse-backed on disk; see generator caveat in `ground-truth/`)
- `run_id` filter is intentionally omitted from exports — these CSVs are snapshots of the single current run

## Gotchas

- `chargeback.csv` shows `UNATTRIBUTABLE` first — this is 35 TiB (larger than Symphony's 18.7 TiB number from the PDF). The discrepancy is because our classifier buckets anything not `DEMO\GG_*` into UNATTRIBUTABLE (which includes `DEMO\GG_AllEmployees`, service accounts, and users), while Symphony's native report excludes GG_AllEmployees from the chargeback category specifically. Update the classifier if you want to match Symphony's donut exactly.
- `dept` column uses `splitByChar('/', file_path)[4]` — Symphony normalizes paths to `/S/Shared/<Dept>/...` with forward slashes. If path shape changes in a future scan, re-validate this extraction.
