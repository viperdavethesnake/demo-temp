# Fix Log — sym02 Dashboards

Running log of what's been verified / changed per panel.
Pairs with `backlog.md` (what's open) and `findings.md` (what the numbers mean).

Canonical dashboard-JSON path: **`dashboards/provisioned/*.json`** (at the repo root).
Apply loop: write JSON there → `POST /api/admin/provisioning/dashboards/reload` → re-render PNG.

---

## 2026-04-20 — Phase 0 verification pass

Verification against the post-fix JSONs. No edits applied in this pass; goal
was to confirm which claimed fixes were actually in the JSON vs. still open.

Scan: full — 9,964,693 files / 77.87 TiB / run_id `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233`.

### sym-exec

| Panel # | Title | Finding | Status |
|---|---|---|---|
| 6 | `% Widens Access (W)` | SQL uses `positionCaseInsensitive(acl_analysis,'W')>0` in place of `Everyone` substring. | ✅ shipped |
| 5 | `% Files Orphaned Owner` | Predicate unchanged: `S-1-%` OR empty OR `positionCaseInsensitive(owner_name,'unresolv')>0`. Reads 10% because the `S-1-%` / empty branches already match the orphan population; `'unresolv'` clause is fragile but not wrong on this data. | ⚠️ open (backlog #5) |
| 4 | `Oldest Modified` | SQL (`min(modified)`) returns a valid DateTime64, but panel has no field override to format as time. Renders as "No data". | ❌ open (backlog #6) |
| 7 | `Capacity by Age Band` | SQL labels correctly as `Active/Warm/Cold/Frozen`. Panel has no `options.legend`, no `options.displayLabels`, and likely no `options.reduceOptions.values=true` — Grafana reduces the 4 rows to a single value and renders as an unlabelled disc. | ❌ open (backlog #6) |
| — | `% Broken DACL Inheritance (B)` tile | Backlog #1 specified both `W` and `B` tiles on sym-exec. Only `W` shipped. | ❌ open (backlog #1) |
| — | Creation-year histogram | Not present. Demo-critical 0b. | ❌ open |
| — | Dept-bytes treemap / stacked bar | Not present. Demo-critical 0d. | ❌ open |
| — | `migrated` tile | Not present. | → Phase 2 (no signal; see below) |

### sym-ops

| Panel # | Title | Finding | Status |
|---|---|---|---|
| 4 | `Broken Inheritance` | SQL uses `positionCaseInsensitive(acl_analysis,'B')>0`. Case-insensitive match catches both `B` (DACL) and `b` (SACL). | ✅ shipped |
| 3 | `'Everyone' ACL Files` | Substring match on `acl` for `'Everyone'` retained; reads 0 on full scan. Backlog #1 called for replacement with a widens-access count tile; not done. | ⚠️ stale sentinel |
| 7 | `'Everyone' / Open Exposure — Top Paths` | Same substring match; table empty on full scan. | ⚠️ stale sentinel |
| 2, 6 | Orphan-SID panels | Still include `'unresolv'` clause in predicate. | ⚠️ open (backlog #5) |
| — | Widens-access count tile | Not present. Backlog #1 Ops half. | ❌ open |
| — | ACL-pattern classifier panel | Not present. Demo-critical 0e. | ❌ open |
| — | Service-account panel | Not present. Demo-critical 0f. | ❌ open |

### sym-cfo

| Panel # | Title | Finding | Status |
|---|---|---|---|
| 3 | `Potential Monthly Savings` | Filter pivoted to `last_accessed < now()-INTERVAL 3 YEAR`. | ✅ shipped |
| 6 | `Quick Wins — Large & Stale (>1GiB, >3yr)` | Same pivot; `last_accessed` replaces `modified`. | ✅ shipped |
| 7 | `Frozen Capacity by Extension` | Same pivot. | ✅ shipped |
| 4 | `Capacity Owned by Orphan SIDs` | Orphan predicate still includes `'unresolv'`. | ⚠️ open (backlog #5) |
| — | Chargeback tile (Symphony page-7 parity) | Not present. Would reproduce the native report's chargeback donut for cross-check. | ❌ open |
| — | `migrated` tile | Not present. | → Phase 2 |
| — | `storage_class` breakdown | Not present. | → Phase 2 |

### sym-arch

| Panel # | Title | Finding | Status |
|---|---|---|---|
| 1 | `Top-Level Folders by Capacity` | Extraction uses `splitByChar('/', file_path)[4]`. | ✅ shipped |
| 4 | `Cold Capacity — Top Folders` | Same extraction. Cold filter still `modified < now()-INTERVAL 3 YEAR` (see consistency issue #1 below). | ✅ shipped extraction, ⚠️ `modified` basis |
| 3 | `Extension × Age Matrix` | Columns remain `active_b`, `warm_b`, `cold_b`, `frozen_b`. Regex fieldConfig override applies `bytes` units, but visible column headers unchanged. | ❌ open — add display aliases |
| 5 | `Name+Size Duplicate Clusters` | Unchanged; noisy heuristic. | → Phase 2 (backlog #4 — needs scan-policy + schema change) |
| — | Dormancy-by-dept heatmap | Not present. Demo-critical 0c. | ❌ open |
| — | `storage_class` breakdown | Not present. | → Phase 2 |

---

## Issues surfaced during Phase 0 (not in backlog yet)

1. **`modified` vs `last_accessed` inconsistency across dashboards.** sym-cfo uses `last_accessed` for cold. sym-exec Age Band and sym-arch Cold Top Folders / Extension × Age Matrix still use `modified`. A VAR report citing "X TiB cold" will pull different numbers from different dashboards. Align customer-facing "cold" language on `last_accessed`, or add suffix labels ("by last access" / "by last modified") so both are honest.

2. **HANDOFF.md IT value drift.** HANDOFF says "IT on top at 13.7 TiB". `dept-breakdown.csv` (generated from the same live query) says `IT 14.81 TiB`. Truth = 14.81 TiB (per CSV + findings.md); HANDOFF is stale prose. Fix opportunistically.

3. **Generator-narrative framing is not VAR-deliverable-safe.** Per `ground-truth/README.md` and `build-recipe-and-caveats.md`, "Deadbeat Corp acquisition" / "ghost employees" are demo-stage framings only. Any Phase 1 annotation on the 2019-bulge panel needs customer-generic wording (e.g., "2019 creation-year bulge — investigate origin").

---

## 2026-04-20 — Phase 0 follow-up

### Column-presence result on sym02 scan

Via Claude Code on sym02:

- `migrated`: 0 true / 9,964,693 false → **0.000% migrated**. Column populated, nothing stubbed on this share.
- `storage_class`: 1 distinct value, empty string, all 9.96M rows.
- `storage_state`: 1 distinct value, empty string, all 9.96M rows.

**Decision:** backlog items #2 (`migrated` tile) and #3 (`storage_class`/`state` breakdown) parked until a tiered / real-customer scan arrives. No signal on this data.

### Apply loop

- Authoritative JSONs: `dashboards/provisioned/*.json` (bind-mounted into Grafana container via `docker-compose.yaml`).
- Provisioning config: `updateIntervalSeconds: 30`, `allowUiUpdates: true`. UI edits are non-durable; disk files are truth.
- Apply sequence: write JSON to provisioned dir → `POST http://localhost:3000/api/admin/provisioning/dashboards/reload` (admin basic-auth) → re-render PNG via `GET /render/d/<uid>?width=1920&height=1200&from=now-10y&to=now&kiosk=1` (service-account bearer) → copy render to `exports/dashboards/<uid>.png`.

### Repo cleanup

Three copies of each dashboard JSON existed previously (`/dashboards/`, `/dashboards/provisioned/`, `/exports/dashboards/`) with measurable drift. Canonical path is now `dashboards/provisioned/*.json` only. The root-level `/dashboards/sym-*.json` and `/exports/dashboards/sym-*.json` copies were deleted. PNGs in `/exports/dashboards/` retained as post-apply render snapshots.

---

## Phase 1 starting point — sym-exec

Ordered for the next pass:

1. Add `% Broken DACL Inheritance (B)` stat tile. SQL: `100.0 * countIf(positionCaseInsensitive(acl_analysis,'B')>0) / count()`. Expected: ~92.56%.
2. Fix `Oldest Modified` fieldConfig. Add `unit: "dateTimeFromNow"` so DateTime64 renders as "10 years ago".
3. Fix `Capacity by Age Band` pie: add `options.reduceOptions.values=true` (likely root cause of single-slice yellow disc), `options.legend`, `options.displayLabels`, and `fieldConfig.defaults.color.mode = "palette-classic"`.
4. Add creation-year histogram (0b) with a customer-generic annotation on 2019.
5. Add dept-bytes viz (0d). Treemap vs stacked bar TBD.

Items 1–3 are this pass; 4–5 next. `migrated` tile dropped to Phase 2.

---

## 2026-04-20 — Phase 1 apply #1 (commit `fc65bbeb`)

Pushed items 1–3 to sym-exec. Render report from Claude Code:

| Change | Expected | Actual | Status |
|---|---|---|---|
| B tile added | ~92.56%, red | 92.6%, red | ✅ shipped |
| W tile (unchanged) | ~4.06% | 4.06% orange | ✅ |
| Age Band pie config | 4 labelled slices + legend | Frozen 74% / Cold 19% / Warm 4% / Active 3%, donut, legend with values+% | ✅ shipped |
| Oldest Modified fieldConfig | "N years ago" | "No data" (unchanged) | ❌ not fixed |

### Oldest Modified root cause

The ClickHouse plugin returns `min(modified)` as a typed time field. The stat panel's default reducer filters to numeric fields and drops the time column before any unit formatter applies — "No data" is the stat-panel fallback when zero numeric fields remain. `fieldConfig.defaults.unit = "dateTimeFromNow"` alone doesn't fix it because the field was already discarded.

### Fix #2 queued (commit next)

Change the rawSql on panel id=4 from `SELECT min(modified) AS oldest` to `SELECT toUnixTimestamp64Milli(min(modified)) AS oldest`. Int64 ms-since-epoch survives the numeric-field filter; `dateTimeFromNow` unit then formats it as "N years ago". Panel config unchanged beyond the unit. One-line SQL change.

### Cross-dashboard consistency note

Age Band pie on sym-exec reads Frozen (3y+) = 74% **by `modified`**. findings.md headline says 69.5% dormant **by `last_accessed`**. Both correct for their definition — write-cold is a larger population than read-cold here (files get read but not modified). This is Phase 0 issue #1. Flagging again so we don't quote the wrong number in a VAR report. Final alignment call still pending.

### Sanity check on pie totals

Pie legend values: 57.4 + 14.9 + 3.12 + 2.52 = 77.94 TiB. Matches overview.csv total of 77.87 TiB within rounding. ✅

---

## 2026-04-20 — Phase 1 apply #2 (this commit)

One-line SQL change on sym-exec panel id=4 to fix Oldest Modified. Items 4–5 not in this commit — separate concern, separate push.
