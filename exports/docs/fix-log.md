# Fix Log — sym02 Dashboards

Running log of what's been verified / changed per panel.
Pairs with `backlog.md` (what's open) and `findings.md` (what the numbers mean).

Canonical dashboard-JSON path: **`dashboards/provisioned/*.json`** (at the repo root).
Apply loop: write JSON there → `POST /api/admin/provisioning/dashboards/reload` → re-render PNG.

---

## Phase 1 sym-exec — shipped

Six iterations (`fc65bbeb` → `61c4ce7`). B tile, Oldest Modified cast, Age Band pie options, year histogram (with per-field unit overrides + xField pin), Capacity by Department treemap via marcusolsson-treemap-panel. Treemap visual polish imperfect; accepted. Data correct, story reads.

---

## Phase 1 sym-ops — shipped (`8a48db7` → `b1fc524`)

Widens Access (W) count tile (panel 3, replaces stale Everyone sentinel, 404,714). ACL Pattern Classifier added and then dropped — scan's acl column stores raw SDDL not resolved names, no substring match was possible. Orphan Worklist expanded to full width in its place. Service Account Footprint added (panel 9). Cross-dashboard `'unresolv'` cleanup on sym-exec #5, sym-cfo #4, sym-ops #2 + #6.

**Parked for later:** ACL name resolution on future scans (Scan Policy option in AdminCenter). If enabled, `acl` repopulates with `DEMO\DL_Share_*` strings and a string-match classifier becomes viable.

---

## Phase 1 sym-cfo + sym-arch (this commit)

### sym-cfo — Chargeback by Dept Group (panel id=8, new)

- Position: `{x:12, y:13, w:12, h:9}` — right of Frozen Capacity by Extension table.
- Type: piechart donut (same proven config as sym-exec's Age Band pie).
- SQL: `multiIf(owner_name LIKE 'DEMO\GG_%' AND owner_name != 'DEMO\GG_AllEmployees', owner_name, 'UNATTRIBUTABLE') → chargeback_group, sum(size) → bytes`.
- Classifier scope: **matches Symphony's native page-7 Chargeback Report** — excludes GG_AllEmployees from attributable, bucketing it with non-GG_* (svc accounts, builtins, users, orphans) as UNATTRIBUTABLE. Per source-data/README.md, this yields ~18.7 TiB UNATTRIBUTABLE matching the PDF (vs. ~35 TiB if we included GG_AllEmployees). Decision: customer cross-check trumps completeness.
- Expected render: UNATTRIBUTABLE ~18.7 TiB + ~15 DEMO\GG_* dept rings. Legend right with value + percent.

### sym-arch — three changes

**Panel 3 (Extension × Age Matrix): column display aliases.** Added `fieldConfig.overrides` with `displayName` properties: `active_b → Active`, `warm_b → Warm`, `cold_b → Cold`, `frozen_b → Frozen`, `extension → Extension`. No SQL change. Title updated to "(capacity, by modified)" to make the basis explicit.

**Panel 4 (Cold Top Folders): `modified` → `last_accessed`.** SQL filter changed; title updated to "Cold Capacity — Top Folders (by last_accessed, candidates to archive)". Aligns cold-basis with sym-cfo. Partially resolves Phase 0 consistency issue #1 — the Age Band pie on sym-exec still uses `modified`; title on that now says "by modified" implicit, may revisit if VAR report narrative needs alignment across all three.

**Panel 7 (new): Dormancy by Department.** Table with cell-background coloring.
- Position: `{x:0, y:38, w:24, h:10}` — bottom full-width.
- SQL: per-dept `pct_aging_1y`, `pct_dormant_3y`, `pct_ancient_5y` via `countIf(last_accessed < now() - INTERVAL N YEAR) / count()`. HAVING files > 1000 (drops tail), ORDER BY pct_dormant_3y DESC LIMIT 16.
- Column display: `dept → Dept`, `pct_aging_1y → 1y+`, `pct_dormant_3y → 3y+`, `pct_ancient_5y → 5y+`, `files → Files`.
- Cell coloring via `custom.cellOptions.type: "color-background"` with thresholds per column (green/orange/red, boundaries tuned tighter for 5y+).
- Expected: LEGACY_R&D / LEGACY_Engineering should dominate the red end; QA / Ops / HR should be red on 3y+; Vendors should be green on 3y+ (per dormancy-by-dept.csv).

### sym-arch final layout

- y=0, h=10: Top Folders (w=12) + Size Distribution (w=12)
- y=10, h=10: Extension × Age Matrix w=24 (with aliases)
- y=20, h=10: Cold Top Folders (w=12, by last_accessed) + Dup Clusters (w=12)
- y=30, h=8: ACE Complexity w=24
- y=38, h=10: Dormancy by Department w=24 (new)

---

## Phase 1 across all four dashboards — complete on this commit

Remaining open items are either parked (ACL name resolution, treemap polish) or deferred to Phase 2 (migrated tile, storage_class/state). No Phase 1 work outstanding.

## What's next

- Render verification of this commit on sym-cfo + sym-arch.
- Cross-track: material numbers on sym02 have shifted from the partial-scan figures baked into the v0.2 PDF deliverables. When the other chat track resumes, the refresh should incorporate the updated numbers surfaced here (see earlier commits' fix-log entries).
- Phase 2 is a separate session; triggers are a real tiered-storage scan (unblocks `migrated`, `storage_class`) and/or Scan Policy with name resolution (unblocks ACL pattern classifier).
