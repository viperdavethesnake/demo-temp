# Symphony native scan report

Exported from AdminCenter for the same scan run that populated the Grafana dashboards. This is what a customer would see without any custom dashboarding — use it as the reference point when deciding what to improve or replace.

## File

- `sym02-full-scan.pdf` — the full report (7 pages, Microsoft Print to PDF, image-only, no text layer)
- `page-1.png` … `page-7.png` — individual pages rendered at 150 DPI for screen viewing

## What each page shows

| Page | Content | Designer relevance |
|---|---|---|
| 1 | **Directory Usage** (folder-by-folder bytes, files, dirs) + **ACL Analysis Summary** (6 hygiene categories, folder + file counts) | The Directory Usage table drives the "IT bloat" story. The ACL summary is authoritative at folder level (647 broken-inheritance folders, 20 protected). |
| 2 | **30 Day Review — Bytes Used** for Last Modified / Last Accessed / Created | Recency view. Spike on 19 Apr is a scan-day artifact (dataset was created 19-20 Apr). |
| 3 | **30 Day Review — File Count** for the same three timestamps | Same as page 2 but counts instead of bytes. |
| 4 | **Long-term Trend — Bytes Used** cumulative over 10 years | Shows the S-curve of data accumulation. Slight step at -7Y = 2019 Deadbeat cohort. |
| 5 | **Long-term Trend — File Count** + **File Type Breakdown — Bytes Used** donut | File Type donut: .PDF dominates bytes (19.2 TiB), .BAK (12.5 TiB), .LOG (11.5 TiB), .ZIP (9.2 TiB) — big-but-rare files. |
| 6 | **File Type — File Count** + **File Owner Breakdown** (bytes, count) + **ADS Breakdown** | Owner donuts show GG_IT/GG_Training top. ADS = only `Zone.Identifier` (1.42M files, Windows SmartScreen marker). |
| 7 | **Chargeback Report** — bytes attributed per GG_\* global group | Key page. `UNATTRIBUTABLE = 18.7 TiB (22%)` — the orphan + service-account + built-in admin slice that Symphony can't map to a dept. Our `exports/source-data/chargeback.csv` reproduces this. |

## Using this for design

- **Grafana dashboards cover a superset of Symphony's native report** (dept breakdown, year histogram, dormancy-by-dept, orphan-SID worklist, etc.) — don't just duplicate pages 1–7.
- **Match visual language where it helps** (donut for ownership, vertical bars for activity) but differentiate where Grafana's interactivity helps (drill-down on dept, time-range picker on trend panels).
- **The PDF is intentionally low-interactivity** — it's a static snapshot for email. Designer target is a live, drillable experience.
