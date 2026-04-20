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

(Full Phase 0 tables omitted here for brevity — see earlier commits for the detailed per-panel grid. This version keeps only the running apply log from this point forward.)

---

## Phase 1 sym-exec — shipped

- apply #1 (`fc65bbeb`): B tile, pie options, Oldest Modified fieldConfig. Pie + B green; Oldest Modified still broken (DateTime64 dropped by stat panel reducer).
- apply #2 (`c232f6d`): rawSql cast `toUnixTimestamp64Milli(min(modified))`. "10 years ago" ✅.
- apply #3 (`d7a8e1a`): year histogram v1. X-axis showed "2.02 K" (unit-leak).
- apply #4 (`e7d104d`, render `d09a964`): per-field unit overrides + `xField` pin. Histogram ✅.
- apply #5 (`406bd72` + `8b395b9`): treemap plugin install + Capacity by Department panel. Plugin loads; size/color imperfect.
- apply #6 (`61c4ce7`): color palette + height bump + colorByField. Visual polish imperfect; **accepting as-is and moving on** — story reads, data correct, further iteration not worth the tokens.

sym-exec Phase 1 complete. Five new / fixed panels: B tile, Oldest Modified, Age Band pie, year histogram, dept treemap.

---

## 2026-04-20 — Phase 1 sym-ops (this commit)

Four changes to sym-ops + a cross-dashboard correctness fix.

### Panel changes

| Panel # | Before | After | Reason |
|---|---|---|---|
| 2 | Orphan-SID count with `'unresolv'` clause | Same query, `'unresolv'` clause dropped | Fragile substring on Symphony wording; `S-1-%` OR empty already catches the orphan population (confirmed 10% matches overview.csv). Backlog #5. |
| 3 | `'Everyone' ACL Files` count (reads 0, stale sentinel) | `Widens Access (W)` count | Demo-critical; `acl` literal 'Everyone' is zero on this dataset, W flag is the real signal. Expected ~404,566 files (4.06% × 9.96M). |
| 6 | Orphan worklist with `'unresolv'` | Same query, `'unresolv'` clause dropped | Same reason as #2. |
| 7 | `'Everyone' / Open Exposure — Top Paths` (empty on full scan) | `ACL Pattern Classifier` | Demo-critical 0e. `multiIf` buckets on raw `acl`: ProperAGDLP (`DL_Share_`) / LazyGG (`DEMO\GG_`) / Everyone / Deny / OrphanSid-ACE / Other. First-match wins, so a file with both DL_Share_ AND GG_ is classified Proper. |
| 8 | Top 20 Owners barchart, `w=24` full-width | Same query, `w=12` | Shrunk to make room for new svc-accounts table beside it. |
| 9 (new) | — | `Service Account Footprint` table | Demo-critical 0f. `owner_name LIKE 'DEMO\svc_%'`. Expected 10 rows, svc_antivirus leading at 1.31 TiB. |

### Cross-dashboard `'unresolv'` cleanup (same commit)

- sym-exec panel 5 (`% Files Orphaned Owner`): same predicate tightening.
- sym-cfo panel 4 (`Capacity Owned by Orphan SIDs`): same predicate tightening.

No visible number change expected — the `'unresolv'` branch wasn't firing on this data, so 10% / 7.77 TiB stay the same. Cleanup is for correctness / robustness.

### Layout after this commit (sym-ops)

- y=0, h=3: 5 stat tiles (Files / Orphan-SID / Widens-W / Broken-B / Mod-24h).
- y=3, h=10: Orphan Worklist (w=12) + ACL Pattern Classifier (w=12).
- y=13, h=8: Service Account Footprint (w=12) + Top 20 Owners (w=12).

---

## Phase 1 remaining

- sym-cfo: chargeback-parity tile.
- sym-arch: dormancy-by-dept heatmap (0c), Extension × Age Matrix column aliases, cold-basis alignment (`modified` vs `last_accessed`).
