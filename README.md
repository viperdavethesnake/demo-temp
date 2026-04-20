# demo-temp — Panzura Symphony lab + Grafana dashboards

Working lab on **`PANZURA-SYM02`** (Windows Server + WSL2 Ubuntu-24.04 + Docker). Symphony AdminCenter scans a synthetic 10 M-file messy NAS into ClickHouse; Grafana surfaces the data as four audience-specific dashboards, rendered for handoff.

## Orient yourself

- **Handing the dashboards to a designer?** → [`exports/HANDOFF.md`](exports/HANDOFF.md)
- **Resuming work on the lab?** → [`RESUME.md`](RESUME.md)
- **Understanding the stack?** → [`ARCHITECTURE.md`](ARCHITECTURE.md), [`SYSTEM_INFO.md`](SYSTEM_INFO.md)
- **Iterating on dashboards?** → [`docs/backlog.md`](docs/backlog.md) (ranked), [`docs/findings.md`](docs/findings.md) (ground-truth cross-validation)

## Layout

| Path | What |
|---|---|
| `docker-compose.yaml` + `.env.example` | Stack: ClickHouse + Grafana + grafana-image-renderer on a shared docker network |
| `grafana/provisioning/` | Datasource (`clickhouse` uid) + dashboard-provider YAML |
| `dashboards/` | Original wrapped exports (`sym-*.json`) + `dashboards/provisioned/` (unwrapped, mounted into Grafana) |
| `docs/` | Working notes + `docs/dashboards/*.png` live-rendered snapshots |
| `exports/` | Self-contained designer handoff pack (JSON + PNG + CSV + SQL + PDF) |
| `scan-report/` | Symphony's native AdminCenter 7-page PDF (and page renders) |
| `edit_dashboards.ps1` | Helper: one-shot SQL substitutions across the 4 provisioned JSONs |
| `watch_db.sh` | WSL poll loop for `symphony.scan_results` during active scans |

## Secrets

Plaintext credentials live in `.env` and `renderer_tokens.md`; both are gitignored. `.env.example` documents the shape. Grafana admin / ClickHouse user / service-account tokens are lab-only (`P@ssw0rd`-tier); regenerate if anything leaves this host.

## One-command bring-up

```powershell
wsl -d Ubuntu-24.04 -- bash -c "cd /mnt/c/Users/Administrator/Documents/claude/symphony && docker compose up -d"
```

Grafana → http://192.168.66.112:3000/ · admin / `P@ssw0rd`
