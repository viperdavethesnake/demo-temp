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

`migrated` tile dropped to Phase 2. Items shipped iteratively below.

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

## 2026-04-20 — Phase 1 apply #2 (commit `c232f6d`)

One-line SQL change on sym-exec panel id=4: `SELECT toUnixTimestamp64Milli(min(modified)) AS oldest`. Render report from Claude Code:

| Change | Expected | Actual | Status |
|---|---|---|---|
| Oldest Modified | "N years ago" | "10 years ago" (red) | ✅ fixed |
| B / W / pie | no regression | 92.6% B, 4.06% W, pie 4 slices unchanged | ✅ |

"10 years ago" matches min modified of 2016-04-20 exactly against today's 2026-04-20. Phase 1 items 1–3 all green.

---

## 2026-04-20 — Phase 1 apply #3 (commit `d7a8e1a`): item 0b first attempt

Added Creation Year Distribution barchart (id=10) below the pie+owners row.

Render report from Claude Code:

| Check | Expected | Actual | Status |
|---|---|---|---|
| 11 bars (2016–2026) | yes | 11 bars | ✅ |
| 2019 bar visibly taller | 959K vs 354K–429K neighbours | 959K vs 418K/354K/394K/429K, clearly double-ish | ✅ |
| X-axis labels categorical | "2016".."2026" | "2.02 K" repeated, last two "2.03 K" | ❌ broken |
| Info icon next to title | yes | ⓘ visible | ✅ |
| No regressions top row / pie | all unchanged | all unchanged | ✅ |

### Root cause on x-axis labels

"2.02 K" / "2.03 K" is the `short` unit formatter applied to year values: 2016/1000 = 2.016 → "2.02 K". So Grafana was treating the year column as numeric AND applying `fieldConfig.defaults.unit = "short"` to the x-axis.

Two contributing factors:
- The ClickHouse plugin (or Grafana's barchart auto-type-detection) coerced `toString(toYear(...))` back to numeric because the values looked numeric. Compare to the Top-10-Owners barchart which works: owner_name has backslashes, impossible to coerce, so the "bytes" unit stayed on the bytes field only.
- `defaults.unit` leaked onto the x-axis even though it was intended for file counts.

### Fix #4 queued (this commit)

Three changes to panel id=10:

1. **Drop `fieldConfig.defaults.unit`**. Replace with per-field `overrides`: `year` → unit `"none"` + axisLabel "Year"; `files` → unit `"short"` + axisLabel "Files". Scopes the formatter to only the fields it's meant for.
2. **Add `options.xField = "year"`**. Explicitly pins year as the x-axis dimension — no auto-detection ambiguity between year and files.
3. **Add `options.legend.showLegend = false`** and `options.showValue = "auto"`. Single-series barchart; legend is noise, value labels on bars help readability.

Also simplified SQL: dropped the `toString(toYear(...))` cast since it didn't help and was being undone. Year now numeric in SQL; unit override on the Grafana side does the work.

---

## 2026-04-20 — Phase 1 apply #4 (this commit)

Fix-up for x-axis rendering on the year histogram. Expected render:

- X-axis: categorical labels "2016" … "2026".
- Y-axis: file counts in short unit ("1.7M", "2.5M", etc.).
- 2019 bar clearly taller than 2016–2018, 2020.
- No legend (single series).
- Axis labels "Year" (bottom) and "Files" (left).

---

## Phase 1 remaining

- 0d dept-bytes treemap on sym-exec — paused pending `marcusolsson-treemap-panel` plugin install on sym02.
- (Then Phase 1 for sym-ops, sym-cfo, sym-arch per the original persona order.)
