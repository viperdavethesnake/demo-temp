# Resume — Panzura Symphony Lab

Last saved: 2026-04-19 (post-reboot session)

## ⚠️ REBOOT PENDING — read this first when resuming

User is rebooting the host to:
1. **Attach a new data disk** to the VM
2. **Re-attach the Panzura Symphony Next ISO** (CD-ROM) — `E:` drive is currently empty/0 bytes; the Admin Guide (`E:\Administration_Guide_2026_1.html`) will be available again after the ISO is mounted.

After reboot, before doing anything else:
1. Re-launch the WSL keepalive (the VM does NOT stay up on its own — see "Windows host" section). Open a terminal and run:
   ```
   wsl -d Ubuntu-24.04 -- bash -c "sleep infinity"
   ```
   Leave it open for the rest of the session.
2. Run the "After reboot — verification checklist" further down (WSL IP, portproxy, ClickHouse from Windows).
3. Mount/format the new data disk if it shows up in `Get-Disk` as RAW. (No decision yet on what it's for — confirm with user.)
4. Confirm `E:` is mounted and the Admin Guide is readable.

## Where we left off (just before reboot)

- Symphony 2026.1 Admin Tools + Agent installed on `panzura-sym02.demo.panzura`
- AD configured (LDAP + AdminCenter AD group `SymphonyAdmin`)
- WSL2 / Ubuntu 24.04 / Docker set up
- ClickHouse + Grafana containers running
- Reconfigured ClickHouse to match the reference VM (env-var creds `symphony/symphony/symphony`)
- **Symphony AdminCenter → ClickHouse Test: WORKING** ✅ (user confirmed "works"). Required keepalive process (see below) — `vmIdleTimeout` config does not function in WSL 2.6.3.0.
- ISO got dismounted on previous reboot — Admin Guide currently inaccessible.

## Creds — all of them

### Active Directory (`demo.panzura`)
- Admin user: `david` / `P@ssw0rd` (member of `Domain Admins`, `SymphonyAdmin`)
- Symphony AD group: `SymphonyAdmin`

### Grafana
- URL: http://localhost:3000 (or http://192.168.66.112:3000)
- Admin: `admin` / `P@ssw0rd`

### ClickHouse
- HTTP: http://localhost:8123 (or http://192.168.66.112:8123)
- Native: `localhost:9000`
- User / pw: `symphony` / `symphony`
- Database: `symphony`
- `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1` (user can manage grants)

## Symphony → ClickHouse connection (retry this in AdminCenter after reboot)

- Driver class: `com.clickhouse.jdbc.Driver` (pre-installed)
- JDBC URL: `jdbc:clickhouse://localhost:8123/symphony`
- User: `symphony`
- Password: `symphony`

## Running containers — managed by docker compose

Compose root: `C:\Users\Administrator\Documents\claude\symphony\` (= `/mnt/c/Users/Administrator/Documents/claude/symphony/` in WSL).

```bash
cd /mnt/c/Users/Administrator/Documents/claude/symphony
docker compose up -d       # start everything
docker compose ps          # status
docker compose logs -f grafana
docker compose down        # stop (volumes + network persist — external)
```

Services (all on `symphony` user network):

| Service    | Image                                       | Host ports          |
|------------|---------------------------------------------|---------------------|
| clickhouse | clickhouse/clickhouse-server:latest         | 8123, 9000          |
| grafana    | grafana/grafana:latest                      | 3000                |
| renderer   | grafana/grafana-image-renderer:latest       | internal 8081 only  |

- `symphony/.env` holds `RENDERER_TOKEN` (shared between grafana & renderer) and `GRAFANA_ADMIN_PASSWORD`
- Volumes `grafana-data` + `clickhouse-data` are **external** — compose won't delete them on `down`
- Network `symphony` is **external** — created once, referenced by compose
- ClickHouse still mounts `/srv/clickhouse/users.d/` (RW, entrypoint writes `default-user.xml` there on first start; `best-effort.xml` stays put)

### Grafana provisioning (declarative — no clicking around)

- `grafana/provisioning/datasources/clickhouse.yaml` — ClickHouse datasource, `uid=clickhouse` (matches dashboards)
- `grafana/provisioning/dashboards/providers.yaml` — file provider, scans `/var/lib/grafana-dashboards`
- `dashboards/provisioned/sym-{arch,cfo,exec,ops}.json` — unwrapped (no `{meta,dashboard}` wrapper) dashboard bodies, auto-imported into Grafana folder **Symphony**
- `dashboards/sym-*.json` — original full-exports (kept for reference; NOT mounted)

### Renderer

- Grafana env: `GF_RENDERING_SERVER_URL=http://renderer:8081/render`, `GF_RENDERING_CALLBACK_URL=http://grafana:3000/`, `GF_RENDERING_RENDERER_TOKEN=${RENDERER_TOKEN}`
- Renderer env: `AUTH_TOKEN=${RENDERER_TOKEN}`
- Grafana service-account `renderer` (Admin) + bearer token in `symphony/renderer_tokens.md`
- End-to-end verified: `GET /render/d/sym-exec/...` → 1600×900 PNG (`symphony/render_sym-exec.png`)

## Windows host — persistent configuration in place

- `C:\Users\Administrator\.wslconfig` (survives reboot):
  ```
  [wsl2]
  vmIdleTimeout=2147483647
  ```
  *Intent:* prevent WSL VM idle-shutdown so containers stay warm for Symphony.
  **VERIFIED (WSL 2.6.3.0): this setting is ignored.** Tried `-1` and a max-int positive value;
  in both cases the distro still went `Stopped` ~60s after the last command (full `wsl --shutdown`
  applied between attempts). Config is left in place but it is NOT what's keeping the VM up.

- **Keepalive (the actual mechanism keeping the VM warm):** run a long-lived foreground process —
  `wsl -d Ubuntu-24.04 -- bash -c "sleep infinity"` — in a persistent terminal/window.
  As long as that wsl.exe stays alive on Windows, the VM stays Running and containers stay warm.
  If that terminal is closed, VM idle-shuts-down within ~60s and the next Symphony Test will
  timeout while WSL+Docker+ClickHouse cold-start. Re-launch the keepalive after every reboot.

- `netsh portproxy` rules (listen 0.0.0.0 → WSL VM 172.30.173.170):
  - 8123, 9000, 3000
  - Caveat: if WSL gets a different VM IP after reboot, these need refreshing. See "After reboot" below.

- Windows Defender Firewall: disabled on Domain/Private/Public profiles (all three).

## After reboot — verification checklist

Run these from an admin PowerShell or terminal:

```powershell
# 1. WSL should auto-start on first use (containers come up via --restart unless-stopped)
wsl -d Ubuntu-24.04 -- docker ps --format "{{.Names}} {{.Status}}"
# Expect: clickhouse + grafana + renderer all "Up"
# If any container is missing, bring stack up via compose:
#   wsl -d Ubuntu-24.04 -- bash -c "cd /mnt/c/Users/Administrator/Documents/claude/symphony && docker compose up -d"

# 2. Check WSL VM IP (may have changed)
wsl -d Ubuntu-24.04 -- bash -c "ip -4 addr show eth0 | grep 'inet '"
# Expect: inet 172.30.xxx.xxx/20

# 3. Compare with current portproxy rules
netsh interface portproxy show v4tov4

# 4. If WSL IP changed, refresh portproxy:
$wsl = (wsl -d Ubuntu-24.04 -- bash -c "hostname -I | awk '{print $1}'").Trim()
netsh interface portproxy reset
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8123 connectaddress=$wsl connectport=8123
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=9000 connectaddress=$wsl connectport=9000
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=3000 connectaddress=$wsl connectport=3000

# 5. Sanity-check ClickHouse from Windows
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8123/?user=symphony&password=symphony" -Method POST -Body "SELECT currentUser()"
# Expect: symphony

# 6. Symphony AdminCenter service
Get-Service pzs_admincenter
# If StartType=Automatic and it was running before reboot, it'll come back up.

# 7. Open AdminCenter web UI → Settings → DB connections → Edit ClickHouse → Test

# 8. (optional) Render sanity — should produce a valid PNG
$tok = "<glsa_*_token — see renderer_tokens.md, redacted here for GitHub push protection>"
Invoke-WebRequest -Headers @{Authorization="Bearer $tok"} -OutFile "$env:TEMP\render_check.png" -Uri "http://localhost:3000/render/d/sym-exec/symphony-executive-cto?width=800&height=400&from=now-24h&to=now"
# Expect: PNG file, nonzero size
```

## Next steps (after connection Test succeeds)

1. In AdminCenter: create a **Scan Policy** with "Export Metadata" enabled, output to the ClickHouse DB connection.
2. AdminCenter suggests CREATE TABLE SQL tailored for ClickHouse (DateTime64 columns) — accept it.
3. Run the Scan Policy (pick a small Source first).
4. Grafana dashboards are already provisioned (folder `Symphony`, uids `sym-exec` / `sym-cfo` / `sym-ops` / `sym-arch`). Once the Scan Policy populates data they should light up automatically — the ClickHouse datasource is wired with uid `clickhouse`.

## Files that persist

| Path | What |
|---|---|
| `C:\Users\Administrator\Documents\claude\symphony\SYSTEM_INFO.md` | Component versions and layout |
| `C:\Users\Administrator\Documents\claude\symphony\ARCHITECTURE.md` | Data flow & decisions |
| `C:\Users\Administrator\Documents\claude\symphony\RESUME.md` | This file |
| `C:\Users\Administrator\Documents\claude\symphony\docker-compose.yaml` | Compose stack definition |
| `C:\Users\Administrator\Documents\claude\symphony\.env` | Shared renderer token + admin password |
| `C:\Users\Administrator\Documents\claude\symphony\grafana\provisioning\` | Datasource + dashboard provider YAMLs |
| `C:\Users\Administrator\Documents\claude\symphony\dashboards\*.json` | Original full-export dashboards (reference) |
| `C:\Users\Administrator\Documents\claude\symphony\dashboards\provisioned\*.json` | Unwrapped dashboards (mounted into Grafana) |
| `C:\Users\Administrator\Documents\claude\symphony\renderer_tokens.md` | Shared renderer token + SA bearer |
| `C:\Users\Administrator\.wslconfig` | WSL config |
| `/srv/clickhouse/users.d/best-effort.xml` (inside WSL) | ClickHouse profile setting |

## Known gotchas

- **Cold-start timing** is the root cause of every "Symphony can't connect" error — when WSL is `Stopped`, the JDBC connect triggers a VM+container cold start (~10-15s) and Symphony's driver times out at ~21s on attempt 1/4. Fix is in "Windows host — persistent configuration" above: `vmIdleTimeout=` a large positive int **+** a foreground `sleep infinity` keepalive. The literal `-1` value is silently ignored by WSL.
- **FQDN `panzura-sym02.demo.panzura` resolves to IPv6 link-local first** — some JDBC clients try IPv6 first, get a fast-fail, and give up. Use `localhost` or the LAN IP instead.
- Admin guide is `E:\Administration_Guide_2026_1.html`. The only ClickHouse-specific guidance in it is in §G.2.1 and §G.3.3: driver pre-installed + `date_time_input_format=best_effort`. No container install instructions anywhere.
