# System Info — Panzura Symphony Lab

Snapshot: 2026-04-19

## Host

- Hostname: `panzura-sym02.demo.panzura`
- LAN IP: `192.168.66.112`
- OS: Microsoft Windows Server 2025 Standard (build 26100.32690)
- Role: AD Domain Controller + Global Catalog for `demo.panzura`, also runs Panzura Symphony AdminCenter and Agent
- Certificate Authority: `demo-PANZURA-SYM02-CA` (self-signed, valid until 2036-04-18, in Local Computer → Trusted Root)

## Active Directory

- Domain: `demo.panzura` (NetBIOS: `DEMO`)
- Symphony AD group: `SymphonyAdmin` (`CN=SymphonyAdmin,CN=Users,DC=demo,DC=panzura`)
- Test admin user: `david` (`david@demo.panzura`), password `P@ssw0rd`
  - Member of: `SymphonyAdmin`, `Domain Admins`, `Domain Users`

## Panzura Symphony

- Version: 2026.1
- Components installed on this host: Admin Tools (AdminCenter + DrTool), Agent
- AdminCenter Windows service: `pzs_admincenter` (runs as `LocalSystem`, Tomcat-based)
- AdminCenter install path: `C:\Program Files\Panzura Symphony\AdminTools`
- JDBC drivers: `clickhouse-jdbc-all-symphony.jar` in `...\AdminTools\jdbc_drivers\`
- Install media: `E:\` (also `Administration_Guide_2026_1.html`, `README_2026_1.txt`)
- AD auth: LDAP to `panzura-sym02.demo.panzura:3269` (Secure LDAP, single Global Catalog)

## WSL

- WSL version: 2.6.3.0
- Default version: 2
- Distro: `Ubuntu-24.04` (Ubuntu 24.04.4 LTS, kernel `6.6.87.2-microsoft-standard-WSL2`)
- Default user: `david` (uid 1000, sudo group, `docker` group)
- WSL VM IP at snapshot: `172.30.173.170` (can change on WSL restart)

## Docker

- Version: `29.4.0` (build `9d7ad9f`), Docker CE from official apt repo
- Storage driver: `overlayfs`
- Docker network (user-defined): `symphony`
- Docker volumes: `clickhouse-data`, `grafana-data`

## ClickHouse

- Container: `clickhouse`
- Image: `clickhouse/clickhouse-server:latest` (server version **26.3.9.8**, official build)
- Published ports: `8123/tcp` (HTTP), `9000/tcp` (native)
- Config mount: `/srv/clickhouse/users.d/symphony-users.xml` → `/etc/clickhouse-server/users.d/`
- Users:
  - `default` — no network access (entrypoint-disabled, as expected)
  - `david` / `password` — access_management=1, bound to `::/0`
- Profile setting (required by Symphony): `date_time_input_format = best_effort`
- Databases: `symphony` (empty until first Symphony DB export), plus built-ins

## Grafana

- Container: `grafana`
- Image: `grafana/grafana:latest` (version **13.0.1**)
- Published port: `3000/tcp`
- Plugins installed (via `GF_INSTALL_PLUGINS`):
  - `grafana-clickhouse-datasource`
- Plugins present in image: `grafana-exploretraces-app`, `grafana-lokiexplore-app`, `grafana-metricsdrilldown-app`, `grafana-pyroscope-app`
- No datasources or dashboards provisioned yet

## Windows → Container Access

- Windows Defender Firewall: disabled on Domain/Private/Public profiles
- `netsh portproxy` rules (listen on `0.0.0.0`, forward to WSL VM):

  | Listen | → | Forward |
  |---|---|---|
  | `0.0.0.0:8123` | → | `172.30.173.170:8123` |
  | `0.0.0.0:9000` | → | `172.30.173.170:9000` |
  | `0.0.0.0:3000` | → | `172.30.173.170:3000` |

- Caveat: if WSL restarts and picks up a different VM IP, these rules go stale and need refreshing.

## Endpoints

| Service | From host | From LAN |
|---|---|---|
| ClickHouse HTTP | http://localhost:8123 | http://192.168.66.112:8123 |
| ClickHouse native | localhost:9000 | 192.168.66.112:9000 |
| Grafana | http://localhost:3000 | http://192.168.66.112:3000 |
| Symphony AdminCenter | https://localhost (via service) | via host FQDN |

## Symphony JDBC connection (for AdminCenter DB output)

- Driver class: `com.clickhouse.jdbc.Driver` (pre-installed)
- URL: `jdbc:clickhouse://localhost:8123/symphony`
- User / password: `david` / `password`
