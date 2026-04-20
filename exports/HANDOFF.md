# Symphony dashboards — designer handoff pack

This folder is a self-contained snapshot of the four Grafana dashboards built on top of the Panzura Symphony scan of the synthetic 10 M-file demo dataset. Everything a designer needs to iterate on the dashboards without touching the running stack.

**Snapshot date:** 2026-04-20
**Source scan:** run_id `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233` (9,964,693 files · 77.87 TiB / 85.6 TB logical)
**Grafana version:** 13.0.1
**ClickHouse version:** 26.3.9.8
**Data source plugin:** `grafana-clickhouse-datasource` (uid `clickhouse`)

## What's in this folder

```
exports/
├── HANDOFF.md                    ← you are here
├── dashboards/                   4× JSON + 4× PNG render (1920×1200, kiosk=1, from=now-10y)
│   ├── sym-exec.json / .png      Executive (CTO)
│   ├── sym-cfo.json  / .png      Finance (CFO)
│   ├── sym-ops.json  / .png      Operations
│   └── sym-arch.json / .png      Storage Architect
├── docs/                         Working notes
│   ├── README.md                 stack overview, URLs, login
│   ├── dashboards.md             per-dashboard: audience, panels, known quirks
│   ├── findings.md               ground-truth cross-validation + observations
│   └── backlog.md                ranked improvements (demo-critical first)
├── source-data/                  12× CSV snapshots of scan_results aggregations
│   ├── overview.csv              KPIs one row
│   ├── dept-breakdown.csv        bytes/files per dept
│   ├── year-distribution.csv     creation-year histogram (2019 bulge visible)
│   ├── chargeback.csv            Symphony-style chargeback allocation
│   ├── ownership.csv             DeptGroup/User/Orphan/Admin/Svc split
│   ├── acl-analysis-flags.csv    top acl_analysis flag strings
│   ├── top-orphan-sids.csv       ex-employee file footprints
│   ├── service-accounts.csv      svc_* footprint
│   ├── extensions-by-bytes.csv
│   ├── extensions-by-count.csv
│   ├── size-buckets.csv
│   └── dormancy-by-dept.csv
├── scan-report/                  Symphony's native AdminCenter PDF report
│   ├── sym02-full-scan.pdf       7-page exported report
│   ├── page-1.png … page-7.png   150 DPI renders
│   └── README.md                 what each page shows
├── ground-truth/                 Pointer to the generator's own docs
│   └── README.md                 the "why" behind the demo data
└── sql-examples/
    ├── queries.sql               all SQL used by the dashboards (annotated)
    └── export-source-data.sh     regenerate the source-data CSVs
```

## How to read this pack

1. **Open `scan-report/page-1.png` through `page-7.png`** — that's the out-of-the-box Symphony report your dashboards are augmenting/replacing. Starting point.
2. **Open `dashboards/*.png`** — see what our Grafana version currently shows.
3. **Read `docs/dashboards.md`** — for each of the four dashboards: who it's for, what panels exist, and what's broken.
4. **Read `docs/findings.md`** — cross-validation against the generator's ground truth. Every headline number was verified.
5. **Read `docs/backlog.md`** — ranked list of improvements, "demo-critical" section first (storylines the dashboards don't yet surface).
6. **Read `ground-truth/README.md`** — points at the demo-data team's own documentation. Do not modify their spec; reference it.
7. **Use `source-data/*.csv`** when designing new panels — 12 pre-aggregated CSVs covering the common slices (dept, year, owner, ACL). Ready to paste into Figma, Sheets, or a static mock without standing up the live stack.
8. **Use `sql-examples/queries.sql`** when adding SQL-backed panels — working ClickHouse dialect, already run against the real data.

## State of the four dashboards

All four are provisioned in Grafana folder `Symphony` and rendering against the full scan:

| Dashboard | Key metric current value | Known quirks (see `docs/backlog.md`) |
|---|---|---|
| sym-exec | 9.96M files / 77.9 TiB / 10.00% orphan / 4.06% widens access | "Oldest Modified" stat = "No data" (panel config); "Capacity by Age Band" pie lacks labels; no year histogram |
| sym-cfo  | $1.79K/mo current · $1.07K/mo projected archive savings · 7.77 TiB orphan-owned | Cost model ignores egress/retrieval fees; no chargeback tile matching Symphony's native report |
| sym-ops  | 995,991 orphan-SID files · 9.2M broken-inheritance files · 0 Everyone | Missing: ACL-pattern classifier (AGDLP/LazyGG/etc.), service-account panel |
| sym-arch | Dept breakdown with IT on top at 13.7 TiB logical / 11 TiB cold | Dup detection filename+size (noisy); heatmap is Extension×Age (modified), could be Dept×Age (accessed) |

## Demo storylines the dashboards *don't yet* show

From the generator's canonical `demo-narrative-and-widgets.md`:

1. **2019 Deadbeat Corp acquisition** — 500K-file bulge in CT=2019. No year histogram anywhere.
2. **ACL pattern sankey** — lazy `GG_*` direct ACEs (336 folders) vs. proper `DL_Share_*` (4,924 folders). Data is in the raw `acl` string; no panel bucketizes it.
3. **Folder-level broken inheritance** — 20 deterministic sensitive folders (vs. the 9M file-level noise). Requires folder-level aggregation; `scan_results` is per-file.
4. **Service-account sprawl** — 500K files across 10 `svc_*` accounts. No dedicated tile.
5. **Dormancy-by-dept heatmap** — 70% of data untouched 3+ years, with per-dept variance. No heatmap panel yet.

Adding any of these is mechanical once you know the SQL — it's already in `sql-examples/queries.sql`.

## Rebuilding a live stack from this pack

If a designer wants to run Grafana themselves against this data:

1. Drop the JSONs into `/etc/grafana/provisioning/dashboards/json/` (or mount directory) and provision a ClickHouse datasource with `uid: clickhouse` pointing at a ClickHouse holding `symphony.scan_results`.
2. The 22-column schema: see the opening `CREATE TABLE` in `sql-examples/queries.sql` comments or ask for the full DDL.
3. Load `source-data/*.csv` into that ClickHouse table to reproduce the snapshot without rerunning Symphony against a real share. Note: CSVs are aggregations — for per-file fidelity, a fresh scan is required.

## Contacts / follow-ups

- Dashboard bugs, new panel requests → follow `docs/backlog.md`
- Data shape questions → the generator team's `demo-narrative-and-widgets.md` is authoritative
- Infra questions (how Grafana/ClickHouse/renderer are wired) → `docs/README.md` cheatsheet + the parent `symphony/RESUME.md` on the host
