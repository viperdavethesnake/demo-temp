# Dashboards

Four dashboards in folder `Symphony`, one per audience. All read from `symphony.scan_results` filtered by a `$run_id` variable.

## sym-exec — Executive (CTO)

http://192.168.66.112:3000/d/sym-exec

**Audience:** CTO / leadership — "what shape is our data in, one screen".

**Panels:**
- Total files, total bytes, unique owners, oldest file — headline stats
- % orphaned owners (unresolved SID / `S-1-*` / empty name)
- % Everyone-accessible (substring match on `acl` for literal "Everyone")
- Age distribution by size (Active <90d / Warm 90d-1y / Cold 1-3y / Frozen 3y+)
- Top owners by bytes

**Quirks:**
- "Oldest Modified" stat reads "No data" despite `min(modified)` returning a valid timestamp — stat panel needs field override.
- "Capacity by Age Band" pie chart renders unlabelled — panel config, not data.
- "% Everyone" metric reads 0% on this dataset (no Everyone-SID grants in the `acl` column at file level). Real signal lives in `acl_analysis` flag `W`.

## sym-cfo — Finance (CFO)

http://192.168.66.112:3000/d/sym-cfo

**Audience:** Finance — "what does this data cost and where's the savings".

**Panels:**
- Total bytes
- Current monthly cost: `bytes / 1 TiB × $hot_rate`
- Projected archive savings: cold (3y+ modified) bytes × ($hot_rate − $archive_rate)
- Bytes owned by unresolved SIDs
- Top extensions by bytes
- Large old files (> 1 GB, > 3 yr modified)
- Archive-candidate extensions with projected savings

**Variables:** `$hot_rate`, `$archive_rate` (USD per TiB per month).

**Quirks:**
- Uses `modified`, not `last_accessed` — over-estimates archival savings for write-cold-but-read-hot files.
- Cost model ignores egress, retrieval, and per-request fees.

## sym-ops — Operations

http://192.168.66.112:3000/d/sym-ops

**Audience:** Storage ops — "what needs cleanup".

**Panels:**
- Total files
- Orphans (unresolved SIDs)
- Everyone-accessible count
- Broken-inheritance count (`parent_acl != acl`)
- Recently active (modified <24h)
- Orphan-owner breakdown by SID
- "Everyone" parent directories
- Top owners by file count

**Quirks:**
- Broken-inheritance heuristic fires on any subfolder with added ACEs (legit customization ≠ broken inheritance). Symphony's pre-computed `acl_analysis` flag `B` is the correct signal — not used here. See `backlog.md`.

## sym-arch — Storage Architect

http://192.168.66.112:3000/d/sym-arch

**Audience:** Storage architect — "where's the mass, where's the waste".

**Panels:**
- Top folders by bytes (regex extracts 3rd path segment — **broken for this dataset**, see below)
- File size bucket distribution (<1K / 1K–1M / 1M–1G / 1G–1T / >1T)
- Extension × age heatmap
- Cold top folders (>3y modified)
- Duplicate candidates (same filename + size, > 1 MB)
- ACE count distribution (semicolons in `acl`)

**Quirks:**
- Top-folder extraction collapses everything to one bar (`Shared`) because Symphony normalizes paths to `/S/Shared/<Dept>/…` and the regex stops one segment short. Replace with `splitByChar('/', file_path)[4]` to get dept-level breakdown. See `backlog.md` item 0a.
- Dup detection by filename+size is noisy (thumbnails, empty files, boilerplate). Content-hash dedup would be stronger — enable "Metadata hashes" on the Scan Policy and add a `hash` column.
