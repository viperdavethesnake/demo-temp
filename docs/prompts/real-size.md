# Prompt — real / on-disk size for the Symphony demo reports

Open this in a fresh chat. Goal: decide how to surface *real* (physical, allocation-aware) file size in the Grafana dashboards, because the synthetic-sparse lab is inflating the logical numbers and it's starting to matter for demo credibility.

---

## The problem in one paragraph

The lab at `PANZURA-SYM02` generated 10 M files totalling **~85.6 TB logical** on a 2 TB NTFS volume using Windows sparse files — physical footprint is **~1.2 TB**. Symphony's Scan Policy captured `Length` (the logical / nominal size as reported by `GetFileSize` / `Get-ChildItem.Length`) into `symphony.scan_results.size`. All four dashboards sum that column and show "77.87 TiB" (= 85.6 TB decimal). For the demo narrative that's the intended number — it's what a customer's applications and backup software would see. But for *the look of the report* we need a second size column that reflects **what's actually on disk**, so panels can optionally show physical capacity (or a physical-vs-logical delta, e.g. "you have 85 TB of logical data on 1.2 TB of primary storage — your tiering is earning its keep"). Right now there's no such column — Symphony doesn't export allocation-aware bytes, and `storage_class` / `storage_state` (which could hint at this on a tiered volume) are empty on this scan.

## What I already confirmed

- `symphony.scan_results` has exactly one size column: `size UInt64`. No `physical_size`, `allocated_size`, `on_disk_bytes`.
- `SELECT sum(size) FROM symphony.scan_results` = **85,613,506,678,784** bytes (85.61 TB / 77.87 TiB), matching the generator's declared logical-target of 85.6 TB *exactly*. So `size` = logical, not physical.
- The generator's `dataset-snapshot.md` says physical footprint ≈ 1.2 TB, i.e. ~1.4 % of logical. Every file on `S:\Shared` was created sparse.
- `storage_class` / `storage_state` columns came back 100 % empty string on the 9.96 M rows — Symphony doesn't populate them on a plain SMB/local scan. These are CloudFS-tier concepts.
- `migrated` = false for every row (0.000 %). Also expected — nothing here is stubbed.

## What "real size" probably means (need confirmation in the new chat)

Two plausible interpretations of the user's ask — pick one before designing:

**(A) Physical / on-disk size.** The NTFS-allocated byte count per file, i.e. what `GetCompressedFileSize` or `fsutil file queryallocranges` would report. For sparse files this is ~0 for most of them. Aggregating gives ~1.2 TB across the whole share. Useful if the report story is "primary-tier capacity" or "what a backup would actually copy." **Undersells the demo** — the dashboards would drop from 77 TiB to 1.2 TB overnight.

**(B) Logical-but-validated, labelled "On Disk" / "Capacity" etc.** The current number (85.6 TB) already *is* the real operational size the customer pays for on primary; the user might just want the tile labels and units to read more naturally (e.g. "85.6 TB" in decimal TB instead of "77.9 TiB" in binary, or "On-disk capacity" rather than "Total Logical Size"). This is a cosmetics/labelling change, not a data-collection change.

**(C) Both — panel option.** Add a second column, let panels choose which to sum. Dashboards can have "Logical" and "Allocated" tiles side by side to tell the tiering story.

## Options for capturing physical size (if A or C)

Ordered cheap → expensive. All of them require a second-pass walk of `S:\Shared` on the demo host; Symphony won't go back and fill it.

1. **PowerShell `Get-ItemProperty` + `fsutil file queryallocranges`** per file — walks the tree, writes `(file_uri, allocated_bytes)` to a CSV or a sibling ClickHouse table `symphony.file_physical`. Easy to write; slow at 10 M files (hundreds of seconds to low hours).
2. **P/Invoke `GetCompressedFileSize`** from a single PowerShell or small .NET tool — no fsutil fork per file, same data. Should finish in < 30 min for 10 M files on local NVMe.
3. **C# / Rust tool using `FSCTL_GET_RETRIEVAL_POINTERS`** (direct MFT extent read) — fastest, ~minutes, overkill for this one-off. Worth it only if we plan to refresh physical sizes across many rebuilds.
4. **Change the generator to write non-sparse** — impossible on this 2 TB volume for 85 TB of logical; dead option.
5. **Don't collect physical at all; synthesise it from a known sparsity ratio** — e.g. `physical ≈ size * 0.014`. Statistically accurate at the aggregate level (matches the 1.4 % total), hides real per-file variance. Fast. Dishonest-ish for a per-file column; fine for a tile that says "approximate on-disk total."
6. **Re-run Symphony with a different Scan Policy option** — worth a five-minute check of the policy wizard to see if there's a "storage-aware size" / "allocated size" toggle. I don't recall one from the admin guide excerpts, but double-check §G.3 in `F:\Administration_Guide_2026_1.html` first.

## My recommended path (opinion, not committed)

Assuming interpretation **(C)** (both columns, dashboards choose):

1. **Five-minute sanity check of the Symphony Scan Policy UI** — if it has an "allocated size" option, enable it and rescan. Free data column, no custom tooling.
2. If not, write a **small .NET helper** (option 2): walks `S:\Shared`, calls `GetCompressedFileSize` per file, outputs a CSV with two columns `file_uri,allocated_bytes`. A few hundred lines of C# or PowerShell.
3. Load the CSV into a new ClickHouse table `symphony.file_physical (file_uri String, allocated UInt64) ENGINE = MergeTree ORDER BY file_uri` (matches `scan_results` order-by for efficient JOINs).
4. Add a Grafana variable `$size_metric = Logical | Physical`, and panels that want the choice use `CASE WHEN $size_metric = 'Physical' THEN fp.allocated ELSE sr.size END`.
5. Add two new tiles on sym-exec for the narrative: **Logical Capacity** (85.6 TB) and **On-Disk Capacity** (1.2 TB) side by side. The delta *is* the story.

## What the new chat should do first

1. **Confirm interpretation** — ask whether "real size" means physical, logical-relabelled, or both. Don't start coding until that's nailed down.
2. **Check the Scan Policy wizard** for a physical/allocated option (5 min).
3. If no native support, decide between synthetic approximation (fast, aggregate-only) and per-file capture (accurate, needs tooling).
4. Before writing the helper, spot-check two or three files manually with `fsutil file queryallocranges "S:\Shared\Shared_2019.log"` so we know the API returns what we expect on this VM.

## Pointers the new chat needs

- **Running ClickHouse** — `http://localhost:8123/?user=symphony&password=symphony` (from this box or WSL). Table: `symphony.scan_results`. Active run_id: `c915d505-3f5b-4bae-963b-c521b7fd63e3-1776679196233`.
- **Demo share** — `S:\Shared` (on this host). Generator docs at `C:\Users\Administrator\Documents\pan-demo-data\docs\demo-dataset\`.
- **Symphony admin guide** — ISO mounted at `F:\` (was `E:\` pre-reboot); §G.3 covers Scan Policy DB export options.
- **Dashboards repo / provisioning path** — `C:\Users\Administrator\Documents\claude\symphony\dashboards\provisioned\*.json`, bind-mounted into Grafana via `docker-compose.yaml`. Apply loop: edit JSON → `POST /api/admin/provisioning/dashboards/reload` → render via `/render/d/<uid>?…`. See `docs/README.md` in this same repo for specifics.
- **Ground truth logical total to hit** — 85.6 TB / 77.87 TiB, 9,962,001 files. Physical should land around 1.2 TB / 1.09 TiB according to the generator. Sanity-check any helper against those numbers.

## Out of scope for the new chat

- Dashboard *layout* changes (year histogram, dept treemap, etc.). Those are Phase 1 items 0b / 0d in `docs/backlog.md` — this chat is still doing them.
- The `migrated` / `storage_class` / `storage_state` tiles. They're deferred until a real tiered-customer scan.
- The per-dashboard Grafana JSON surgery for the new size variable — defer until data is actually available.
