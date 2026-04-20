# Findings

Running log of notable observations from scan data.

---

## 2026-04-20 — Full scan (9.96M rows, 77.87 TiB) cross-validated against generator ground truth

Generator spec: `C:\Users\Administrator\Documents\pan-demo-data\docs\demo-dataset\` (PanzuraDemo v4.1.0, 10M-file messy NAS).

### Every number in the generator spec matches our scan

| Generator claim | Spec | `scan_results` | |
|---|---:|---:|---|
| Files created | 9,962,001 | 9,964,693 | ✓ (+2.7K — dirs/probes) |
| Logical bytes | 85.6 TB | 77.87 TiB = 85.6 TB | ✓ |
| Dormant (`last_accessed > 3y`) | 69.8% | 69.5% | ✓ |
| Ownership orphan SID | 10.0% | 10.0% | ✓ |
| Ownership svc accounts | 5.0% | 4.99% | ✓ |
| Ownership built-in admin | 5.0% | 5.03% | ✓ |
| 2019 Deadbeat bulge | 9.63% | 9.62% | ✓ |
| IT dept logical | 15.2 TB | 14.81 TiB | ✓ |

Scan is faithful. Every demo story is in `scan_results`. Dashboards just don't draw them.

### ACL hygiene (structurally broken, 93% of files)

| Metric | Count | % of rows |
|---|---:|---:|
| `acl_analysis LIKE '%B%'` — broken DACL inheritance | 6,564,203 | 92.6% |
| `acl_analysis LIKE '%W%'` — may widen access | 269,900 | 3.8% |
| `acl_analysis LIKE '%Z%'` — NULL DACL (open to everyone) | 0 | 0% |
| `acl` contains literal "Everyone" | 0 | 0% |
| `parent_acl != '' AND acl != parent_acl` (naive-broken) | 6,877,367 | 97.0% |

The raw-ACL "Everyone" check on sym-exec reads 0 on this data. Real access-widening risk lives in the `W` flag (3.8% of files), which is not currently surfaced. Naive broken-inheritance overcounts by ~313K vs. the authoritative `B` flag.

### Key demo stories present-but-unshown

1. **2019 Deadbeat acquisition bulge** — 958,842 files created in 2019 (9.62% vs. 3-4% neighbours). No creation-year histogram in any current dashboard.
2. **Dept capacity breakdown** — the entire generator narrative is dept-by-dept. sym-arch's "top folders" bug collapses all dept data into one "Shared" bar.
3. **Orphan SID population** — 10% on the full scan (the Orphanize phase completed after partial scan). sym-exec/sym-ops tiles should now show meaningful values against the new `run_id`.
4. **Service account sprawl** — 500K files (5%), 10 accounts, not isolated in any tile.
5. **Dormancy by access time** — 6.95M files not read in 3+ years. No dormancy tile anywhere. Where we use age we use `modified`, not `last_accessed`.
6. **ACL-pattern classification** — 336 lazy `GG_*` direct ACEs vs 4,924 proper `DL_Share_*` (AGDLP hygiene). Raw `acl` column has this data.

### sym-arch path-segment bug (ground-truth validated)

Symphony normalizes paths to `/S/Shared/<Dept>/…` (forward slashes). Current regex captures segment 3 (`Shared`). With `splitByChar('/', file_path)[4]` the real dept breakdown:

```
IT           14.81 TiB    476K files
Training      7.16 TiB    384K
Marketing     7.10 TiB    731K
Finance       6.66 TiB    834K
Support       6.17 TiB    628K
Sales         5.17 TiB    990K
Users         4.93 TiB   1.52M  (home-dir tree)
Legal         4.83 TiB    825K
QA            3.73 TiB    393K
Procurement   3.32 TiB    654K
HR            3.13 TiB    338K
R&D           2.56 TiB    480K
Engineering   2.37 TiB    460K
Ops           2.16 TiB    373K
Logistics     1.54 TiB    384K
Facilities    1.44 TiB    412K
```

Matches the generator spec within TB/TiB rounding.

### File age distribution

`modified` range: 2016-04-20 → 2026-04-20 (full decade). Creation-year distribution has the expected artifacts:

```
2016   4.19%    (LegacyMess floor)
2017   3.56%
2018   3.95%
2019   9.62%    ← Deadbeat cohort
2020   4.31%
2021  17.24%    (Dormant/LegacyArchive classes pin to Now-3y..5y)
2022  24.66%    (peak of the 2021-23 pinning window)
2023  14.55%
2024   7.71%
2025   6.72%
2026   3.48%
```

The 2021-23 peak is an artifact of the generator's Dormant-class time pinning. Will shift as wall-clock advances.

### Panel anomalies (logged before ground-truth validation)

- **sym-exec "Capacity by Age Band" pie chart** renders as an unlabelled yellow disc.
- **sym-exec "Oldest Modified" stat** shows "No data" despite `min(modified)` returning a valid timestamp. Stat panel needs field override to treat as time.
