# Symphony Dashboard Documentation

Working notes on the four Grafana dashboards fed from `symphony.scan_results` in ClickHouse.

## Files in this folder

| File | Purpose |
|---|---|
| `README.md` | This index |
| `dashboards.md` | Per-dashboard: audience, panels, SQL logic, known quirks |
| `findings.md` | Interesting observations from scan data (growing log) |
| `backlog.md` | Proposed changes / open questions to address later |
| `dashboards/*.json` | Snapshot of the four provisioned dashboard definitions |
| `dashboards/*.png` | Rendered snapshots (regenerate after dashboard edits) |

## Stack cheatsheet

- Grafana: http://192.168.66.112:3000/ (admin / `P@ssw0rd`)
- Dashboard folder: `Symphony`
- Data source: ClickHouse (uid `clickhouse`) → `symphony.scan_results`
- Run selector: the `$run_id` variable dropdown at the top of each dashboard

## Ground-truth cross-reference

The demo data is generator-produced and ground truth lives at
`C:\Users\Administrator\Documents\pan-demo-data\docs\demo-dataset\` — cite that when building new panels. Key files there:

- `dataset-snapshot.md` — actual counts, bytes, distributions
- `demo-narrative-and-widgets.md` — nine demo storylines with suggested widgets + SQL
- `build-recipe-and-caveats.md` — what *not* to claim on stage

## Status

- 2026-04-20 — Full scan loaded: 9.96M rows / 77.87 TiB. All ground-truth numbers (ownership split, 2019 bulge, IT bloat, dormancy) match the generator spec. Dashboards published as-is with demo-story gaps catalogued in `backlog.md`.
