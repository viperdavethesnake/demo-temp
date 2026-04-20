# Architecture — Symphony Scan → ClickHouse → Grafana

## Goal

Turn Panzura Symphony scan output into persistent, queryable storage (ClickHouse) and role-specific dashboards (Grafana) for executive, finance, ops, and storage-architect audiences.

## Data flow

```
           ┌──────────────────────┐
           │  File servers / SMB  │
           │   NAS / volumes      │
           └──────────┬───────────┘
                      │  scan (Symphony Agent)
                      ▼
           ┌──────────────────────┐
           │  Symphony AdminCenter │  ──► reports, tasks, ACL analysis
           │  (Windows service)   │
           └──────────┬───────────┘
                      │  Scan Policy → Export Metadata → database (JDBC)
                      │  driver: com.clickhouse.jdbc.Driver
                      ▼
           ┌──────────────────────┐
           │  ClickHouse          │  table: symphony.scan_results
           │  (Docker in WSL2)    │  keyed by run_id
           └──────────┬───────────┘
                      │  native protocol :9000
                      ▼
           ┌──────────────────────┐
           │  Grafana             │  datasource: grafana-clickhouse-datasource
           │  (Docker in WSL2)    │  dashboards: Executive / CFO / Ops / Architect
           └──────────────────────┘
```

## Host layout (this box)

All services co-located on `panzura-sym02.demo.panzura`:

- Session 0 / Windows services: Symphony AdminCenter (Tomcat, LocalSystem), Symphony Agent, AD DS, wslservice
- Session 0 / WSL VM (Ubuntu 24.04): Docker daemon, ClickHouse container, Grafana container
- Windows → WSL reachability: `netsh portproxy` on `0.0.0.0` → WSL VM IP for 8123 / 9000 / 3000
- LAN reachability: same portproxy rules make services reachable on `192.168.66.112`

## Components

### Symphony AdminCenter
- Source of scans. A Scan Policy can be configured to export per-file metadata to an external database.
- The JDBC driver class (`com.clickhouse.jdbc.Driver`) ships with AdminCenter.
- Required ClickHouse profile setting: `date_time_input_format = best_effort` — applied in our `users.d` config.
- DB Source feature (G.2) and DB output feature (G.3) described in `Administration_Guide_2026_1.html`.

### ClickHouse
- Single user-defined table: `symphony.scan_results` (created by AdminCenter's CREATE TABLE recommendation when configured)
- Row grain: one row per file scanned per `run_id`
- Observed columns referenced by reference dashboards:
  `run_id, size, owner_sid, owner_name, acl, parent_acl, file_path, filename, extension, parent_dir, modified, ace_count, …`
- `run_id` is the standard pivot — all dashboard panels filter `WHERE run_id='$run_id'` so multiple historical scans can coexist.
- Storage: Docker named volume `clickhouse-data` (survives container recreation; wiped if WSL distro is unregistered).

### Grafana
- Single datasource pointing at ClickHouse via native protocol (:9000).
- Reference setup uses user `symphony` against database `symphony` — on this box we can either create a matching CH user or retarget the provisioning to `david`.
- Dashboards (pulled from reference, stored in `reference/`):
  - `sym-exec` — Executive (CTO): 8 panels, capacity / age / exposure headlines
  - `sym-cfo` — Finance (CFO): 7 panels, cost & archive savings
  - `sym-ops` — Operations: 8 panels, orphan SIDs, 'Everyone' ACL, broken inheritance
  - `sym-arch` — Storage Architect: 6 panels, folder / size / extension / duplicate analysis
- Dashboards are file-provisioned on the reference box (`managedBy: classic-file-provisioning`, `readOnly: true`) — i.e. YAML + JSON files mounted into the container under `/etc/grafana/provisioning/`. We haven't pulled those files yet.

## Key addressing

- **Container → container** (within docker network `symphony`): use service name, e.g. Grafana datasource URL `clickhouse:9000`.
- **Windows (AdminCenter service) → ClickHouse**: `jdbc:clickhouse://localhost:8123/symphony` via wslrelay.
  - Session-0 reachability requires wslrelay to be spawned from a context visible to session 0 — which is why we reinstalled WSL with the normal first-run flow (not `--no-launch`) this time.
- **External LAN → services**: `192.168.66.112:{8123,9000,3000}` via `netsh portproxy` rules.

## What's still to do

1. Create a Symphony Scan Policy with **Export Metadata → database** enabled, pointing at `jdbc:clickhouse://localhost:8123/symphony` (user `david` / `password`) with AdminCenter's recommended ClickHouse column layout.
2. Run an initial scan to populate `symphony.scan_results`.
3. Pull the Grafana provisioning files from the reference box (`/etc/grafana/provisioning/datasources/*.yaml`, `/etc/grafana/provisioning/dashboards/*.yaml` + JSON) and mount them into our Grafana container — or recreate them from the dashboard JSON we've already captured.
4. Decide user alignment: either create a ClickHouse user `symphony` to match the reference provisioning, or retarget the datasource YAML to `david`.

## Persistence & fragilities

- Docker volumes persist across container restarts but NOT across `wsl --unregister`.
- WSL VM IP can shift on WSL restart → `netsh portproxy` rules require refresh in that case.
- `wslrelay` is per-session; the Symphony service's ability to reach `localhost:8123` depends on wslrelay being registered where session 0 can reach it. Current install used the normal first-run flow; to be confirmed once AdminCenter's DB connection test passes.
