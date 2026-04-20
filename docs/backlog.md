# Dashboard Backlog

Proposed changes ordered by impact. Demo-critical items first.

## Demo-critical (surface the generator's nine storylines)

Canonical list: `C:\Users\Administrator\Documents\pan-demo-data\docs\demo-dataset\demo-narrative-and-widgets.md`.

0a. **Fix sym-arch top-folder extraction.** One-char change unlocks the dept bloat story. Replace the regex with `splitByChar('/', file_path)[4]`. IT at 14.81 TiB pops to #1 immediately. Currently everything collapses to a single "Shared" bar.

0b. **Add creation-year histogram on sym-exec** — with an annotation on 2019 ("Deadbeat Corp acquisition"). `SELECT toYear(created) AS y, count() FROM scan_results WHERE run_id='$run_id' GROUP BY y ORDER BY y`. This is the demo's signature moment; it's currently invisible.

0c. **Add dormancy-by-dept heatmap on sym-arch.** Rows = dept (via `splitByChar`), cols = age buckets based on `last_accessed`, value = %. The generator's #1 storyline ("70% not touched in 3+ years") has no tile anywhere.

0d. **Add dept-bytes treemap or stacked bar on sym-exec or sym-cfo.** Visualizes the IT-bloat (17.7% of total) story. Uses the same `splitByChar` extraction.

0e. **Add ACL-pattern classifier tile on sym-ops.** CASE bucketing on `acl` → `{ProperAGDLP (DL_Share_*), LazyGG (GG_* direct), OrphanSID-ACE, Everyone, Deny, Other}`. Sankey or stacked bar. Hits the "lazy AGDLP" story head-on.

0f. **Add service-account panel on sym-ops.** `WHERE owner_name LIKE 'DEMO\svc_%'`, table of Owner × files × bytes × folders touched. 500K files, 10 accounts.

0g. **Pivot dormancy metrics to `last_accessed`.** sym-cfo archive-savings currently uses `modified` — write-cold ≠ read-cold. Add a `last_accessed`-based cold set.

## High impact (data-quality / accuracy)

1. **Pivot ACL-hygiene panels to `acl_analysis` flag string.** Replace substring/regex heuristics on raw `acl` / `parent_acl`.
   - sym-exec: swap "% Everyone" tile → "% may-widen-access (W flag)". Add "% broken DACL inheritance (B flag)".
   - sym-ops: replace `parent_acl != '' AND acl != parent_acl` → `acl_analysis LIKE '%B%'`. Add a "widens access" count tile.

2. **Add `migrated` (stub vs primary) tile.** Column exists, unused everywhere. On Panzura this is table-stakes: % of files currently stubbed to archive tier.

3. **Surface `storage_class` / `storage_state`.** Also unused. Reflects where data actually lives on tiered storage.

4. **Content-hash dedup.** Enable "Metadata hashes" on the Scan Policy, add a `hash` column, replace sym-arch's filename+size dup heuristic with hash+size. Way less noise.

## Medium

5. **Orphan-owner detection tightness.** Currently `owner_name LIKE 'S-1-%' OR owner_name='' OR position(owner_name,'unresolv')>0`. The `'unresolv'` substring depends on Symphony's wording. Safer: `owner_sid != '' AND owner_name LIKE 'S-1-%'`.

6. **Panel bugs on sym-exec.** "Oldest Modified" stat → "No data" even though `min(modified)` works. "Capacity by Age Band" pie renders as unlabelled disc. Both panel config, not data.

## Nice to have

7. **Multi-run trend panels.** Once retention stacks up 4-5 runs, add growth/orphan-count/new-Everyone-grants-over-time panels using `run_start_time` as the x-axis.

8. **Per-source filter variable.** `$source` derived from `file_uri` prefix so dashboards can slice by share.

9. **CFO cost model refinements.** Add egress + retrieval/API fee variables.

10. **Folder-level ACL scan.** Demo stories #4 (lazy AGDLP), #5 (broken-inheritance sensitive folders), #6 (Temp folders) are folder-level facts. `scan_results` is file-level. Either reconstruct folder ACLs from per-file `parent_acl`, or run a separate folder scan. The 20 deterministic broken-inheritance folders get drowned in 93% file-level noise without folder aggregation.
