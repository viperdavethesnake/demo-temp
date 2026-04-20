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

(Full Phase 0 tables omitted here for brevity — see earlier commits for the detailed per-panel grid.)

---

## Phase 1 sym-exec — shipped

- apply #1 (`fc65bbeb`): B tile, pie options, Oldest Modified fieldConfig. Pie + B green; Oldest Modified still broken.
- apply #2 (`c232f6d`): `toUnixTimestamp64Milli(min(modified))` cast. "10 years ago" ✅.
- apply #3 (`d7a8e1a`): year histogram v1. X-axis unit leak.
- apply #4 (`e7d104d`, render `d09a964`): per-field unit overrides + `xField` pin. Histogram ✅.
- apply #5 (`406bd72` + `8b395b9`): treemap plugin + Capacity by Department.
- apply #6 (`61c4ce7`): treemap color/height polish. Visual imperfect, **accepted as-is** — data correct, story reads.

sym-exec Phase 1 complete.

---

## 2026-04-20 — Phase 1 sym-ops (commit `8a48db7`)

### Shipped

- Panel 3: `Everyone` count → `Widens Access (W)` count. 404,714 files, red. ✅
- Panel 8: Top 20 Owners barchart shrunk `w=24 → w=12`.
- Panel 9 (new): Service Account Footprint. 10 rows led by svc_antivirus 1.31 TiB. ✅ (10th row partially scrolled out; non-blocking, revisit if persona feedback warrants).
- Panels 2 + 6: orphan predicate `'unresolv'` clause dropped.
- Cross-dashboard: same `'unresolv'` cleanup on sym-exec #5 and sym-cfo #4. No number movement (branch wasn't firing on this data). ✅

### ACL Pattern Classifier (panel 7) — broken, then dropped (`8a48db7` + this commit)

First render returned only two rows: OrphanSid-ACE at 99.97% and Other at 0.03%. All other pattern rows (ProperAGDLP, LazyGG, Everyone, Deny) empty.

**Root cause**: the `acl` column stores **raw SDDL**, not resolved names. Symphony's scan policy didn't resolve ACEs to names for this scan, so domain-local groups (`DL_Share_Finance_RW`), global groups (`DEMO\GG_Finance`), and built-ins are serialized as raw SIDs (`S-1-5-21-…`) or 2-letter SDDL codes (`BA`, `BU`, `SY`, `DU`, `DA`, `WD` for Everyone, `D;` for Deny in ACE-type position). The substrings `DL_Share_` / `DEMO\GG_` / `Everyone` / `DENY` literally don't appear in the data.

Diagnostic counts (Claude Code):
```
countIf(acl LIKE '%DL_Share_%')  = 0
countIf(acl LIKE '%DEMO\\GG_%')  = 0
countIf(acl LIKE '%Everyone%')   = 0
countIf(acl LIKE '%DENY%')       = 0
countIf(acl LIKE '%S-1-5-21%')   = 9,961,769
```

Sample acl value from a row:
```
win:O:S-1-5-21-…-6509G:DUD:AI(A;ID;FA;;;S-1-5-21-…-6572)(A;ID;FA;;;BA)(A;ID;FA;;;SY)(A;ID;0x1200a9;;;BU)
```

### Decision

Dropped panel 7 entirely. Option considered and rejected: porting the classifier to SDDL codes (detect `WD` for Everyone, `D;` in ACE-type position for Deny, RID-range heuristics for GG_ vs DL_). Brittle without an AD SID ↔ name map, and the W/B tiles on the top row already surface the two hygiene flags that matter for VAR narrative.

Expanded panel 6 (Orphan SID Worklist) from `w=12` to `w=24` to fill the space. Cleaner layout, more columns readable.

### Parked for later (new backlog item)

**ACL name resolution on future scans.** If Symphony's Scan Policy has a "resolve ACEs to names" option in AdminCenter, turning it on repopulates `acl` with `DEMO\DL_Share_Finance_RW` style strings, and a string-match classifier becomes viable. Otherwise the acl_analysis flag string (already surfaced via W/B tiles) is the authoritative signal. Not actioning now; note for the next scan-policy review.

### sym-ops final layout

- y=0, h=3: 5 stat tiles (Files / Orphan-SID / Widens-W / Broken-B / Mod-24h).
- y=3, h=10: Orphan SID Worklist, full width.
- y=13, h=8: Service Account Footprint (w=12) + Top 20 Owners (w=12).

sym-ops Phase 1 complete.

---

## Phase 1 remaining

- sym-cfo: chargeback-parity tile (Symphony page-7 donut).
- sym-arch: dormancy-by-dept heatmap (0c), Extension × Age Matrix column aliases, cold-basis alignment (`modified` vs `last_accessed`).
